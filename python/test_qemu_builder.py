from os_autoinst.qemu_builder import QemuBuilder
from os_autoinst.vars import Vars


def test_qemu_builder():
    v = Vars()
    v.set("QEMURAM", "1024")
    v.set("ARCH", "x86_64")

    builder = QemuBuilder(v)
    builder.configure_basics()

    cmd = builder.build()
    print(f"Generated cmd: {cmd}")
    assert "-m" in cmd
    assert "1024" in cmd


if __name__ == "__main__":
    test_qemu_builder()
    print("QemuBuilder test passed!")
