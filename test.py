#!/usr/bin/env python3
import argparse, sys, time
from typing import Optional, Tuple
import serial

START_BYTE = 0xAA
END_BYTE   = 0x55

# Updated command set
CMD_CLEAR   = 0x11        # input<->compute: clear
CMD_COMPUTE = 0x20        # input -> compute: ASCII expression
CMD_RESULT  = 0x21        # compute -> input: ASCII numeric result

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
    """Send a RESULT command with ASCII numeric result (PC acting as compute)."""
    payload = result.encode("ascii", errors="replace")
    if len(payload) > max_data:
        if not truncate:
            raise ValueError(f"result too long for max_data={max_data}")
        payload = payload[:max_data]
    ser.write(build_frame(CMD_RESULT, payload))
    ser.flush()

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
                        s = data.decode("ascii", errors="replace")
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

    p_listen = sub.add_parser("listen", help="Listen and print frames")
    p_listen.add_argument("--hex", action="store_true", help="Also print payload hex")

    p_clear = sub.add_parser("clear", help="Send CLEAR")

    p_comp = sub.add_parser("send-compute", help="Send COMPUTE with ASCII expression")
    p_comp.add_argument("expr", help="Expression to compute (ASCII)")
    p_comp.add_argument("--no-truncate", action="store_true", help="Error if longer than --max-data")

    p_res = sub.add_parser("send-result", help="Send RESULT with ASCII number (PC emulates compute)")
    p_res.add_argument("value", help="Numeric result (ASCII)")
    p_res.add_argument("--no-truncate", action="store_true", help="Error if longer than --max-data")

    args = ap.parse_args()

    try:
        with serial.Serial(args.port, args.baud, timeout=0.01) as ser:
            if args.cmd == "listen":
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
    except serial.SerialException as e:
        print(f"Serial error: {e}", file=sys.stderr)
        sys.exit(2)

if __name__ == "__main__":
    main()
