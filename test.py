# pip install pyserial
import time
import serial

START_BYTE = 0xAA
END_BYTE   = 0x55
BAUD       = 115200
PORT       = "COM4"
TIMEOUT    = 3.0  # seconds (read timeout)

# --- Protocol helpers --------------------------------------------------------

def build_frame(cmd, data_bytes):
    """
    Frame: START, LEN, CMD, DATA..., CHK, END
    LEN = payload length = 1 (CMD) + len(DATA)
    CHK = XOR of CMD and all DATA bytes (LEN not included)
    """
    payload = bytes([cmd]) + bytes(data_bytes)
    length  = len(payload)
    chk = 0
    for b in payload:
        chk ^= b
    frame = bytes([START_BYTE, length]) + payload + bytes([chk, END_BYTE])
    return frame

def parse_frame(buf):
    """
    Parse a full received frame (already aligned to START).
    Returns (cmd, data_bytes). Raises ValueError on parse error.
    """
    if len(buf) < 5:
        raise ValueError("Frame too short")

    if buf[0] != START_BYTE:
        raise ValueError("Bad start byte")

    length = buf[1]
    # Expected total size = 1(START) + 1(LEN) + length(payload) + 1(CHK) + 1(END)
    expected = 1 + 1 + length + 1 + 1
    if len(buf) != expected:
        raise ValueError(f"Bad length: expected {expected}, got {len(buf)}")

    payload = buf[2:2+length]
    cmd = payload[0]
    data = payload[1:]

    chk = 0
    for b in payload:
        chk ^= b

    recv_chk = buf[2+length]
    if recv_chk != chk:
        raise ValueError(f"Checksum mismatch: got 0x{recv_chk:02X}, want 0x{chk:02X}")

    if buf[-1] != END_BYTE:
        raise ValueError("Bad end byte")

    return cmd, data

def read_exact(ser, n):
    """
    Read exactly n bytes or raise TimeoutError.
    """
    out = bytearray()
    deadline = time.time() + TIMEOUT
    while len(out) < n:
        chunk = ser.read(n - len(out))
        if chunk:
            out.extend(chunk)
        if time.time() > deadline:
            raise TimeoutError(f"Timeout reading {n} bytes (got {len(out)})")
    return bytes(out)

def recv_frame(ser):
    """
    Sync to START_BYTE, then read the rest of the frame by LEN.
    Returns raw frame bytes.
    """
    deadline = time.time() + TIMEOUT
    # sync to start byte
    while True:
        b = ser.read(1)
        if b:
            if b[0] == START_BYTE:
                break
        if time.time() > deadline:
            raise TimeoutError("Timeout waiting for START byte")
    # read LEN
    length_bytes = read_exact(ser, 1)
    length = length_bytes[0]
    # read: payload(length) + CHK(1) + END(1)
    rest = read_exact(ser, length + 2)
    return bytes([START_BYTE, length]) + rest

def send_req(ser, cmd, a=None, b=None):
    """
    Send a request with optional 1-2 data bytes, then receive and parse reply.
    Returns (reply_cmd, reply_data_bytes).
    """
    data = []
    if a is not None: data.append(a & 0xFF)
    if b is not None: data.append(b & 0xFF)

    tx = build_frame(cmd, data)
    ser.write(tx)

    rx = recv_frame(ser)
    rcmd, rdata = parse_frame(rx)
    return rcmd, list(rdata), rx, tx

# --- Calculator command IDs --------------------------------------------------

CMD_ADD = 0x01
CMD_SUB = 0x02
CMD_MUL = 0x03
CMD_DIV = 0x04

# Reply is cmd|0x80 (e.g. 0x81 for add, etc.)

def pretty_bytes(bs):
    return " ".join(f"{b:02X}" for b in bs)

# --- Test runner -------------------------------------------------------------

def run_tests():
    with serial.Serial(PORT, BAUD, timeout=0.05) as ser:
        # Flush any junk
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        tests = [
            ("ADD 5+3", CMD_ADD, 5, 3),
            ("SUB 9-4", CMD_SUB, 9, 4),
            ("MUL 7*6", CMD_MUL, 7, 6),
            ("DIV 20/3", CMD_DIV, 20, 2),
            #("DIV 10/0 (div-by-zero guard)", CMD_DIV, 10, 0),
        ]

        for label, cmd, a, b in tests:
            print(f"\n=== {label} ===")
            try:
                rcmd, rdata, raw_rx, raw_tx = send_req(ser, cmd, a, b)
                print(f"TX: {pretty_bytes(raw_tx)}")
                print(f"RX: {pretty_bytes(raw_rx)}")
                expected_rcmd = cmd | 0x80
                if rcmd != expected_rcmd:
                    print(f"[!] Unexpected reply CMD: 0x{rcmd:02X} (expected 0x{expected_rcmd:02X})")

                # Interpret results per spec:
                if cmd in (CMD_ADD, CMD_SUB, CMD_MUL):
                    if len(rdata) != 1:
                        print(f"[!] Unexpected data length: {len(rdata)} (expected 1)")
                    else:
                        print(f"Result (LSB): {rdata[0]} (0x{rdata[0]:02X})")
                elif cmd == CMD_DIV:
                    if len(rdata) != 2:
                        print(f"[!] Unexpected data length: {len(rdata)} (expected 2)")
                    else:
                        q, r = rdata
                        print(f"Quotient: {q} (0x{q:02X}), Remainder: {r} (0x{r:02X})")
                else:
                    print(f"Reply data: {rdata}")

            except TimeoutError as e:
                print(f"[Timeout] {e}")
            except ValueError as e:
                print(f"[ParseError] {e}")
            except serial.SerialException as e:
                print(f"[SerialError] {e}")

            time.sleep(1.0)

if __name__ == "__main__":
    print(f"Opening {PORT} @ {BAUD} 8N1; START=0x{START_BYTE:02X}, END=0x{END_BYTE:02X}")
    run_tests()
    print("\nDone.")
