#!/usr/bin/env python3
import argparse, sys, time, math, re, struct
from typing import Optional, Tuple
import serial

START_BYTE = 0xAA
END_BYTE   = 0x55

CMD_CLEAR      = 0x11
CMD_COMPUTE    = 0x20
CMD_RESULT     = 0x21
CMD_GRAPH_EVAL = 0x22

# Special keys
PI_KEY = 129; SQRT_KEY = 130; SIN_KEY = 131
COS_KEY = 132; TAN_KEY = 133; LN_KEY = 134; LOG_KEY = 135

# ANSI colors for terminal
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def build_frame(cmd: int, data: bytes) -> bytes:
    if len(data) > 254:
        raise ValueError("payload too long")
    n = len(data)
    length = (1 + n) & 0xFF
    chk = cmd
    for b in data:
        chk ^= b
    return bytes([START_BYTE, length, cmd]) + data + bytes([chk, END_BYTE])

def send_result(ser: serial.Serial, result: str, max_data: int = 32, truncate: bool = True) -> None:
    payload = result.encode("ascii", errors="replace")
    if len(payload) > max_data:
        if not truncate:
            raise ValueError(f"result too long")
        payload = payload[:max_data]
    ser.write(build_frame(CMD_RESULT, payload))
    ser.flush()

def send_graph_result(ser: serial.Serial, y_q16_16: int) -> None:
    """Send graph result as 4-byte Q16.16 (little-endian)"""
    if y_q16_16 > 2147483647:
        y_q16_16 = 2147483647
    elif y_q16_16 < -2147483648:
        y_q16_16 = -2147483648
    
    payload = struct.pack('<i', y_q16_16)  # little-endian signed 32-bit
    ser.write(build_frame(CMD_GRAPH_EVAL, payload))
    ser.flush()

def send_clear(ser: serial.Serial) -> None:
    """Send clear command"""
    ser.write(build_frame(CMD_CLEAR, b''))
    ser.flush()

def send_text(ser: serial.Serial, text: str, max_data: int = 32) -> None:
    """Send text to display"""
    payload = text.encode("ascii", errors="replace")
    if len(payload) > max_data:
        payload = payload[:max_data]
    ser.write(build_frame(CMD_RESULT, payload))
    ser.flush()

def parse_stream_find_frame(buf: bytearray) -> Optional[Tuple[int, int, bytes, int]]:
    while True:
        i = buf.find(bytes([START_BYTE]))
        if i < 0:
            buf.clear()
            return None
        if i > 0:
            del buf[:i]
        if len(buf) < 3:
            return None
        L = buf[1]
        total = L + 4
        if len(buf) < total:
            return None
        frame = bytes(buf[:total])
        if frame[-1] != END_BYTE:
            del buf[0]
            continue
        cmd = frame[2]
        N = (L - 1) & 0xFF
        data = frame[3:3+N]
        chk = frame[3+N]
        acc = cmd
        for b in data:
            acc ^= b
        chk_ok = 1 if (acc == chk) else 0
        del buf[:total]
        return (cmd, N, data, chk_ok)

def decode_expression(data: bytes) -> str:
    result = []
    for b in data:
        if b == PI_KEY: result.append("π")
        elif b == SQRT_KEY: result.append("√")
        elif b == SIN_KEY: result.append("sin")
        elif b == COS_KEY: result.append("cos")
        elif b == TAN_KEY: result.append("tan")
        elif b == LN_KEY: result.append("ln")
        elif b == LOG_KEY: result.append("log")
        elif 32 <= b <= 126:
            result.append(chr(b))
        else:
            result.append(f"[{b}]")
    return ''.join(result)

def preprocess_expression(expr: str) -> str:
    expr = expr.replace('π', 'math.pi')
    expr = expr.replace('√', 'math.sqrt(')
    expr = expr.replace('sin', 'math.sin')
    expr = expr.replace('cos', 'math.cos')
    expr = expr.replace('tan', 'math.tan')
    expr = expr.replace('ln', 'math.log')
    expr = expr.replace('log', 'math.log10')
    expr = expr.replace('^', '**')
    expr = re.sub(r'(\d)(\()', r'\1*\2', expr)
    expr = re.sub(r'(\d)(math\.)', r'\1*\2', expr)
    expr = re.sub(r'(\))(\d)', r'\1*\2', expr)
    expr = re.sub(r'(\))(math\.)', r'\1*\2', expr)
    return expr

def evaluate_expression(expr: str, x_value: Optional[float] = None) -> Tuple[bool, str]:
    try:
        python_expr = preprocess_expression(expr)
        namespace = {"__builtins__": {}, "math": math}
        if x_value is not None:
            namespace["x"] = x_value
        result = eval(python_expr, namespace)
        if isinstance(result, (int, float)):
            if result == int(result):
                return (True, str(int(result)))
            else:
                return (True, f"{result:.6g}")
        else:
            return (False, "ERR")
    except Exception as e:
        return (False, "ERR")

def q16_to_float(q16: int) -> float:
    """Convert Q16.16 to float"""
    return q16 / 65536.0

def float_to_q16(f: float) -> int:
    """Convert float to Q16.16"""
    return int(f * 65536.0)

def format_q16(q16: int) -> str:
    """Format Q16.16 as hex and float"""
    f = q16_to_float(q16)
    return f"{f:8.4f} (0x{q16:08x})"

# ============ Server Mode ============
def compute_server(ser: serial.Serial, print_hex: bool = False, verbose: bool = True) -> None:
    buf = bytearray()
    print(f"{Colors.BOLD}{Colors.GREEN}Compute Server with Graph Support Running...{Colors.RESET}")
    print(f"{Colors.CYAN}Listening for COMPUTE and GRAPH_EVAL commands...{Colors.RESET}")
    print(f"(Ctrl-C to stop)\n")
    
    graph_count = 0
    compute_count = 0
    
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
                        compute_count += 1
                        expr_decoded = decode_expression(data)
                        print(f"{Colors.BOLD}[COMPUTE #{compute_count}]{Colors.RESET} Received: {Colors.YELLOW}{expr_decoded!r}{Colors.RESET}")
                        if print_hex:
                            print(f"          Raw hex: {data.hex()}")
                        
                        if not chk_ok:
                            print(f"          {Colors.RED}⚠️  Checksum error!{Colors.RESET}")
                            send_result(ser, "ERR")
                            continue
                        
                        success, result = evaluate_expression(expr_decoded)
                        if success:
                            print(f"          {Colors.GREEN}✓{Colors.RESET} Result: {Colors.BOLD}{result}{Colors.RESET}")
                            send_result(ser, result)
                        else:
                            print(f"          {Colors.RED}✗{Colors.RESET} Error: {result}")
                            send_result(ser, "ERR")
                        print()
                    
                    elif cmd == CMD_GRAPH_EVAL:
                        graph_count += 1
                        if n < 5:
                            print(f"{Colors.RED}[GRAPH_EVAL] Invalid payload length: {n}{Colors.RESET}")
                            continue
                        
                        expr_len = data[0]
                        expr_bytes = data[1:1+expr_len]
                        x_bytes = data[1+expr_len:1+expr_len+4]
                        
                        if len(x_bytes) < 4:
                            print(f"{Colors.RED}[GRAPH_EVAL] Incomplete x value{Colors.RESET}")
                            continue
                        
                        expr_decoded = decode_expression(expr_bytes)
                        x_q16_16 = struct.unpack('<i', x_bytes)[0]  # little-endian signed
                        x_float = q16_to_float(x_q16_16)
                        
                        print(f"{Colors.BOLD}[GRAPH_EVAL #{graph_count}]{Colors.RESET} Expr: {Colors.CYAN}{expr_decoded!r}{Colors.RESET}")
                        print(f"                    x = {format_q16(x_q16_16)}")
                        if print_hex:
                            print(f"                    Expr hex: {expr_bytes.hex()}")
                            print(f"                    x bytes: {x_bytes.hex()}")
                        
                        if not chk_ok:
                            print(f"                    {Colors.RED}⚠️  Checksum error!{Colors.RESET}")
                            send_graph_result(ser, 0)
                            continue
                        
                        # Evaluate with x
                        success, result_str = evaluate_expression(expr_decoded, x_float)
                        
                        if success:
                            try:
                                result_float = float(result_str)
                                result_q16 = float_to_q16(result_float)
                                print(f"                    {Colors.GREEN}✓{Colors.RESET} y = {format_q16(result_q16)}")
                                send_graph_result(ser, result_q16)
                            except:
                                print(f"                    {Colors.RED}✗ Cannot convert to Q16.16{Colors.RESET}")
                                send_graph_result(ser, 0)
                        else:
                            print(f"                    {Colors.RED}✗ Evaluation error{Colors.RESET}")
                            send_graph_result(ser, 0)
                        print()
                    
                    elif cmd == CMD_CLEAR:
                        print(f"{Colors.BOLD}[CLEAR]{Colors.RESET} Received (chk_ok={chk_ok})\n")
                    
                    else:
                        print(f"{Colors.RED}[CMD 0x{cmd:02X}] Unknown command (len={n}, chk_ok={chk_ok}){Colors.RESET}\n")
            else:
                time.sleep(0.001)
    except KeyboardInterrupt:
        print(f"\n{Colors.BOLD}Compute Server Stopped.{Colors.RESET}")
        print(f"Total COMPUTE commands: {compute_count}")
        print(f"Total GRAPH_EVAL commands: {graph_count}")

# ============ Listen Mode ============
def listen_mode(ser: serial.Serial, print_hex: bool = False) -> None:
    buf = bytearray()
    print(f"{Colors.BOLD}{Colors.BLUE}Listen Mode - Monitoring all UART traffic{Colors.RESET}")
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
                    
                    timestamp = time.strftime("%H:%M:%S")
                    chk_str = f"{Colors.GREEN}✓{Colors.RESET}" if chk_ok else f"{Colors.RED}✗{Colors.RESET}"
                    
                    if cmd == CMD_COMPUTE:
                        expr = decode_expression(data)
                        print(f"[{timestamp}] {Colors.YELLOW}COMPUTE{Colors.RESET} {chk_str} len={n}: {expr!r}")
                    elif cmd == CMD_RESULT:
                        result = decode_expression(data)
                        print(f"[{timestamp}] {Colors.GREEN}RESULT{Colors.RESET}  {chk_str} len={n}: {result!r}")
                    elif cmd == CMD_CLEAR:
                        print(f"[{timestamp}] {Colors.CYAN}CLEAR{Colors.RESET}   {chk_str}")
                    elif cmd == CMD_GRAPH_EVAL:
                        if n >= 5:
                            expr_len = data[0]
                            expr = decode_expression(data[1:1+expr_len])
                            x_bytes = data[1+expr_len:1+expr_len+4]
                            if len(x_bytes) == 4:
                                x_q16 = struct.unpack('<i', x_bytes)[0]
                                print(f"[{timestamp}] {Colors.CYAN}GRAPH_EVAL{Colors.RESET} {chk_str} expr={expr!r} x={format_q16(x_q16)}")
                            else:
                                print(f"[{timestamp}] {Colors.CYAN}GRAPH_EVAL{Colors.RESET} {chk_str} [incomplete]")
                        else:
                            y_q16 = struct.unpack('<i', data[:4])[0] if n == 4 else 0
                            print(f"[{timestamp}] {Colors.CYAN}GRAPH_RESULT{Colors.RESET} {chk_str} y={format_q16(y_q16)}")
                    else:
                        print(f"[{timestamp}] {Colors.RED}CMD 0x{cmd:02X}{Colors.RESET} {chk_str} len={n}")
                    
                    if print_hex:
                        print(f"           Hex: {data.hex()}")
            else:
                time.sleep(0.001)
    except KeyboardInterrupt:
        print(f"\n{Colors.BOLD}Listen Mode Stopped.{Colors.RESET}")

# ============ Send Commands ============
def send_command(ser: serial.Serial, text: str) -> None:
    """Send text to FPGA display"""
    print(f"Sending: {text!r}")
    send_text(ser, text)
    print("Sent.")

def clear_command(ser: serial.Serial) -> None:
    """Send clear command"""
    print("Sending CLEAR...")
    send_clear(ser)
    print("Sent.")

# ============ Main ============
def main():
    ap = argparse.ArgumentParser(description="UART tool with graph support")
    ap.add_argument("--port", required=True, help="Serial port")
    ap.add_argument("--baud", type=int, default=115200, help="Baud rate")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_server = sub.add_parser("server", help="Run compute server with graph support")
    p_server.add_argument("--hex", action="store_true", help="Print payload hex")
    p_server.add_argument("--quiet", action="store_true", help="Less verbose")

    p_listen = sub.add_parser("listen", help="Monitor UART traffic")
    p_listen.add_argument("--hex", action="store_true", help="Print payload hex")

    p_send = sub.add_parser("send", help="Send text to display")
    p_send.add_argument("text", help="Text to send")

    p_clear = sub.add_parser("clear", help="Send clear command")

    args = ap.parse_args()

    try:
        with serial.Serial(args.port, args.baud, timeout=0.01) as ser:
            if args.cmd == "server":
                compute_server(ser, print_hex=args.hex, verbose=not args.quiet)
            elif args.cmd == "listen":
                listen_mode(ser, print_hex=args.hex)
            elif args.cmd == "send":
                send_command(ser, args.text)
            elif args.cmd == "clear":
                clear_command(ser)
    except serial.SerialException as e:
        print(f"{Colors.RED}Serial error: {e}{Colors.RESET}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        print(f"\n{Colors.BOLD}Interrupted.{Colors.RESET}")
        sys.exit(0)

if __name__ == "__main__":
    main()