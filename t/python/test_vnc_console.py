from os_autoinst.console import VNCConsole
import struct


def test_vnc_key_event():
    vnc = VNCConsole("test", "localhost", 5900)
    # We can't easily test network here, but we can test struct packing
    # 4 (type), 1 (down), 0 (padding), 0xff1b (esc)
    expected = struct.pack(">BBHI", 4, 1, 0, 0xFF1B)

    # Mock socket
    class MockSocket:
        def __init__(self):
            self.sent_data = b""

        def sendall(self, data):
            self.sent_data += data

    vnc.socket = MockSocket()
    vnc.send_key(0xFF1B, True)

    print(f"Sent data: {vnc.socket.sent_data.hex()}")
    assert vnc.socket.sent_data == expected


if __name__ == "__main__":
    test_vnc_key_event()
    print("VNCConsole test passed!")
