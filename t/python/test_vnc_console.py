from os_autoinst.console import VNCConsole, get_keysym
import struct


def test_vnc_key_event():
    vnc = VNCConsole("test", "localhost", 5900)
    # 4 (type), 1 (down), 0 (padding), 0xff1b (esc)
    expected = struct.pack(">BBHI", 4, 1, 0, 0xFF1B)

    # Mock socket
    class MockSocket:
        def __init__(self):
            self.sent_data = b""

        def sendall(self, data):
            self.sent_data += data

    vnc.socket = MockSocket()
    vnc.send_key(get_keysym("esc"), True)

    print(f"Sent data: {vnc.socket.sent_data.hex()}")
    assert vnc.socket.sent_data == expected


def test_vnc_ikvm_key_event():
    vnc = VNCConsole("test", "localhost", 5900)
    vnc.ikvm = True
    # pack('>BxBHI9x', 4, 1, 0, 0xff1b)
    expected = struct.pack(">BxBHI9x", 4, 1, 0, 0xFF1B)

    class MockSocket:
        def __init__(self):
            self.sent_data = b""

        def sendall(self, data):
            self.sent_data += data

    vnc.socket = MockSocket()
    vnc.send_key(get_keysym("esc"), True)

    print(f"Sent IKVM data: {vnc.socket.sent_data.hex()}")
    assert vnc.socket.sent_data == expected


if __name__ == "__main__":
    test_vnc_key_event()
    test_vnc_ikvm_key_event()
    print("VNCConsole tests passed!")
