#!/usr/bin/env python3
import argparse, sys, time, math, re
from typing import Optional, Tuple
import serial

START_BYTE = 0xAA
END_BYTE   = 0x55

# Updated command set
CMD_CLEAR   = 0x11        # input<->compute: clear
CMD_COMPUTE = 0x20        # input -> compute: ASCII expression
CMD_RESULT  = 0x21        # compute -> input: ASCII numeric result

# Special key codes (from constants.vh)
PI_KEY    = 129
SQRT_KEY  = 130
SIN_KEY   = 131
COS_KEY   = 132
TAN_KEY   = 133
LN_KEY    = 134
LOG_KEY   = 135

def build_frame(cmd: int, data: bytes) -> bytes:
    """
    Build one frame: [START][LEN][CMD][DATA...][CHK][END]
      - LEN = 1 + N  (number of bytes in CMD + DATA)
      - CHK = XOR over CMD and all DATA bytes
    """
    if len(data) > 254:
        raise ValueError("payload too long: max 254 data bytes (LEN = 1 + N must fit in 0..255)")
    n = len(data)
    length = (1 + n) & 0xFF
    chk = cmd
    for b in data:
        chk ^= b
    return bytes([START_BYTE, length, cmd]) + data + bytes([chk, END_BYTE])

def send_clear(ser: serial.Serial) -> None:
    ser.write(build_frame(CMD_CLEAR, b""))
    ser.flush()

def send_compute(ser: serial.Serial, expr: str, max_data: int = 32, truncate: bool = True) -> None:
    """Send a COMPUTE command with ASCII expression."""
    payload = expr.encode("ascii", errors="replace")
    if len(payload) > max_data:
        if not truncate:
            raise ValueError(f"expr too long for max_data={max_data}")
        payload = payload[:max_data]
    ser.write(build_frame(CMD_COMPUTE, payload))
    ser.flush()

def send_result(ser: serial.Serial, result: str, max_data: int = 32, truncate: bool = True) -> None:
    """Send a RESULT command with ASCII numeric result."""
    payload = result.encode("ascii", errors="replace")
    if len(payload) > max_data:
        if not truncate:
            raise ValueError(f"result too long for max_data={max_data}")
        payload = payload[:max_data]
    ser.write(build_frame(CMD_RESULT, payload))
    ser.flush()

def send_error(ser: serial.Serial) -> None:
    """Send ERR as result."""
    send_result(ser, "ERR", max_data=32, truncate=False)

def parse_stream_find_frame(buf: bytearray) -> Optional[Tuple[int, int, bytes, int]]:
    """
    Scan 'buf' for a valid frame and return (cmd, n, data_bytes, chk_ok).
    On success, consumed bytes are removed from 'buf'. Returns None if incomplete.
    Protocol: [START][LEN=L][CMD][DATA... (N=L-1)][CHK][END], total bytes = L + 4.
    """
    while True:
        # find START
        i = buf.find(bytes([START_BYTE]))
        if i < 0:
            buf.clear()
            return None
        if i > 0:
            del buf[:i]
        # need at least START + LEN + CMD + CHK + END = 5 bytes (but we also need LEN)
        if len(buf) < 3:
            return None
        L = buf[1]                   # LEN = 1 + N
        total = L + 4                # START + LEN + (CMD+DATA = L bytes) + CHK + END  => L+4
        if len(buf) < total:
            return None
        frame = bytes(buf[:total])
        if frame[-1] != END_BYTE:
            # bad end; discard this START and continue
            del buf[0]
            continue
        # unpack
        cmd = frame[2]
        N   = (L - 1) & 0xFF
        data = frame[3:3+N]
        chk  = frame[3+N]
        # verify checksum
        acc = cmd
        for b in data:
            acc ^= b
        chk_ok = 1 if (acc == chk) else 0
        del buf[:total]
        return (cmd, N, data, chk_ok)

def decode_expression(data: bytes) -> str:
    """
    Decode expression bytes to human-readable string with special keys.
    Special keys (>127) are replaced with their text representations.
    """
    result = []
    for b in data:
        if b == PI_KEY:
            result.append("π")
        elif b == SQRT_KEY:
            result.append("√")
        elif b == SIN_KEY:
            result.append("sin")
        elif b == COS_KEY:
            result.append("cos")
        elif b == TAN_KEY:
            result.append("tan")
        elif b == LN_KEY:
            result.append("ln")
        elif b == LOG_KEY:
            result.append("log")
        elif 32 <= b <= 126:  # Printable ASCII
            result.append(chr(b))
        else:
            result.append(f"[{b}]")  # Unknown special character
    return ''.join(result)

def preprocess_expression(expr: str) -> str:
    """
    Convert custom expression format to Python-evaluable format.
    Handles:
    - π → math.pi
    - √(...) → math.sqrt(...)
    - sin/cos/tan/ln/log → math.sin/cos/tan/log/log10
    - ^ → **
    - Implicit multiplication: 2π → 2*math.pi, 3(4+5) → 3*(4+5)
    """
    # Replace π with math.pi
    expr = expr.replace('π', 'math.pi')
    
    # Handle √ as sqrt function
    # Convert √X or √(X) to math.sqrt(X) or math.sqrt((X))
    # Simple approach: replace √ with math.sqrt( and balance parentheses
    expr = expr.replace('√', 'math.sqrt(')
    # Need to add closing parenthesis after the number/expression
    # This is tricky - for now, require explicit parentheses: √(expr)
    
    # Replace functions with math. prefix
    expr = expr.replace('sin', 'math.sin')
    expr = expr.replace('cos', 'math.cos')
    expr = expr.replace('tan', 'math.tan')
    expr = expr.replace('ln', 'math.log')      # ln is natural log
    expr = expr.replace('log', 'math.log10')   # log is base-10 log
    
    # Replace ^ with **
    expr = expr.replace('^', '**')
    
    # Replace & (bitwise AND), | (bitwise OR), ~ (bitwise NOT) if used
    # These should work as-is in Python
    
    # Handle implicit multiplication
    # Pattern: digit followed by ( or letter → insert *
    expr = re.sub(r'(\d)(\()', r'\1*\2', expr)  # 2( → 2*(
    expr = re.sub(r'(\d)(math\.)', r'\1*\2', expr)  # 2math.pi → 2*math.pi
    expr = re.sub(r'(\))(\d)', r'\1*\2', expr)  # )2 → )*2
    expr = re.sub(r'(\))(math\.)', r'\1*\2', expr)  # )math.pi → )*math.pi
    
    return expr

def evaluate_expression(expr: str) -> Tuple[bool, str]:
    """
    Evaluate expression and return (success, result_string).
    Returns (True, numeric_result) on success.
    Returns (False, "ERR") on error.
    """
    try:
        # Preprocess expression
        python_expr = preprocess_expression(expr)
        
        # Evaluate
        result = eval(python_expr, {"__builtins__": {}}, {"math": math})
        
        # Convert to integer if whole number, otherwise format nicely
        if isinstance(result, (int, float)):
            if result == int(result):
                return (True, str(int(result)))
            else:
                # Format with reasonable precision
                return (True, f"{result:.6g}")
        else:
            return (False, "ERR")
    except Exception as e:
        print(f"  Evaluation error: {e}", file=sys.stderr)
        return (False, "ERR")

def compute_server(ser: serial.Serial, print_hex: bool = False, verbose: bool = True) -> None:
    """
    Act as compute server: listen for COMPUTE commands, evaluate, send RESULT.
    """
    buf = bytearray()
    print("Compute Server Running...")
    print("Listening for COMPUTE commands from FPGA...")
    print("(Ctrl-C to stop)\n")
    
    try:
        while True:
            chunk = ser.read(256)
            if chunk:
                buf.extend(chunk)
                while True:
                    res = parse_stream_find_frame(buf)
                    if res is None:
                        break
                    cmd, n, data, chk_ok = res
                    
                    if cmd == CMD_COMPUTE:
                        # Decode expression
                        expr_decoded = decode_expression(data)
                        
                        if verbose:
                            print(f"[COMPUTE] Received: {expr_decoded!r}")
                            if print_hex:
                                print(f"          Raw hex: {data.hex()}")
                        
                        if not chk_ok:
                            print(f"          ⚠️  Checksum error!")
                            send_error(ser)
                            continue
                        
                        # Evaluate
                        success, result = evaluate_expression(expr_decoded)
                        
                        if success:
                            if verbose:
                                print(f"          ✓ Result: {result}")
                            send_result(ser, result)
                        else:
                            if verbose:
                                print(f"          ✗ Error: {result}")
                            send_error(ser)
                        
                        if verbose:
                            print()  # Blank line for readability
                    
                    elif cmd == CMD_CLEAR:
                        if verbose:
                            print(f"[CLEAR] Received (chk_ok={chk_ok})\n")
                    
                    elif cmd == CMD_RESULT:
                        # Unexpected - FPGA shouldn't send RESULT to us
                        s = data.decode("ascii", errors="replace")
                        print(f"[RESULT] Unexpected: {s!r} (chk_ok={chk_ok})\n")
                    
                    else:
                        print(f"[CMD 0x{cmd:02X}] Unknown command (len={n}, chk_ok={chk_ok})\n")
            else:
                time.sleep(0.001)
    except KeyboardInterrupt:
        print("\nCompute Server Stopped.")

def listen(ser: serial.Serial, print_hex: bool = False) -> None:
    """
    Read and print frames (useful to watch COMPUTE from input board, or RESULT from compute).
    """
    buf = bytearray()
    print("Listening... (Ctrl-C to stop)")
    try:
        while True:
            chunk = ser.read(256)
            if chunk:
                buf.extend(chunk)
                while True:
                    res = parse_stream_find_frame(buf)
                    if res is None:
                        break
                    cmd, n, data, chk_ok = res
                    
                    if cmd == CMD_COMPUTE:
                        s = decode_expression(data)
                        if print_hex:
                            print(f"[COMPUTE] len={n} chk_ok={chk_ok} hex={data.hex()} expr={s!r}")
                        else:
                            print(f"[COMPUTE] len={n} chk_ok={chk_ok} expr={s}")
                    elif cmd == CMD_RESULT:
                        s = data.decode("ascii", errors="replace")
                        if print_hex:
                            print(f"[RESULT ] len={n} chk_ok={chk_ok} hex={data.hex()} val={s!r}")
                        else:
                            print(f"[RESULT ] len={n} chk_ok={chk_ok} val={s}")
                    elif cmd == CMD_CLEAR:
                        print(f"[CLEAR  ] chk_ok={chk_ok}")
                    else:
                        if print_hex:
                            print(f"[CMD 0x{cmd:02X}] len={n} chk_ok={chk_ok} hex={data.hex()}")
                        else:
                            print(f"[CMD 0x{cmd:02X}] len={n} chk_ok={chk_ok}")
            else:
                time.sleep(0.001)
    except KeyboardInterrupt:
        print("\nStopped.")

def main():
    ap = argparse.ArgumentParser(description="EE2026 UART tool (START/LEN/CMD/DATA/CHK/END)")
    ap.add_argument("--port", required=True, help="Serial port (e.g., COM5 or /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=115200, help="Baud rate (default 115200)")
    ap.add_argument("--max-data", type=int, default=32, help="Max data bytes per frame (default 32)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_server = sub.add_parser("server", help="Run compute server (FPGA → laptop eval → FPGA)")
    p_server.add_argument("--hex", action="store_true", help="Print payload hex")
    p_server.add_argument("--quiet", action="store_true", help="Less verbose output")

    p_listen = sub.add_parser("listen", help="Listen and print frames")
    p_listen.add_argument("--hex", action="store_true", help="Also print payload hex")

    p_clear = sub.add_parser("clear", help="Send CLEAR")

    p_comp = sub.add_parser("send-compute", help="Send COMPUTE with ASCII expression")
    p_comp.add_argument("expr", help="Expression to compute (ASCII)")
    p_comp.add_argument("--no-truncate", action="store_true", help="Error if longer than --max-data")

    p_res = sub.add_parser("send-result", help="Send RESULT with ASCII number")
    p_res.add_argument("value", help="Numeric result (ASCII)")
    p_res.add_argument("--no-truncate", action="store_true", help="Error if longer than --max-data")

    p_err = sub.add_parser("send-error", help="Send ERR as result")

    args = ap.parse_args()

    try:
        with serial.Serial(args.port, args.baud, timeout=0.01) as ser:
            if args.cmd == "server":
                compute_server(ser, print_hex=args.hex, verbose=not args.quiet)
            elif args.cmd == "listen":
                listen(ser, print_hex=args.hex)
            elif args.cmd == "clear":
                send_clear(ser)
                print("CLEAR sent.")
            elif args.cmd == "send-compute":
                send_compute(ser, args.expr, max_data=args.max_data, truncate=not args.no_truncate)
                print("COMPUTE sent.")
            elif args.cmd == "send-result":
                send_result(ser, args.value, max_data=args.max_data, truncate=not args.no_truncate)
                print("RESULT sent.")
            elif args.cmd == "send-error":
                send_error(ser)
                print("ERR sent.")
    except serial.SerialException as e:
        print(f"Serial error: {e}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(0)

if __name__ == "__main__":
    main()