from os_autoinst.qemu_builder import QemuBuilder
from os_autoinst.vars import Vars


def test_qemu_builder():
    v = Vars()
    v.set("QEMURAM", "1024")
    v.set("ARCH", "x86_64")
    v.set("QEMUCPUS", "2")
    v.set("VNC", "1")
    v.set("HDD_0", "test.qcow2")

    builder = QemuBuilder(v)
    builder.configure_basics()
    builder.configure_graphics()
    builder.configure_storage()

    cmd = builder.build()
    print(f"Generated cmd: {cmd}")
    assert "-m" in cmd
    assert "1024" in cmd
    assert "-smp" in cmd
    assert "2" in cmd
    assert "-vnc" in cmd
    assert ":1 share=force-shared" in cmd
    assert "-drive" in cmd
    assert "file=test.qcow2,format=qcow2,if=none,id=drive-hdd0" in cmd


if __name__ == "__main__":
    test_qemu_builder()
    print("QemuBuilder test passed!")
