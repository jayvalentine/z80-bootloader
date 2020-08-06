# ZBoot

ZBoot is a Z80 bootloader and monitor, written in assembly and targeting my homebrew modular Z80 computer.
However, the assembler code could be altered to work in any Z80 machine with a serial port, ROM, and RAM.

## Syscall Interface

The bootloader also provides a "syscall-like" API that loaded applications can use to access the various hardware
interfaces, without needing to know anything about the device details.

The API is also designed for backwards compatibility, so that software compiled to target an old verson of ZBoot can
seamlessly work on a newer version.

### Making Syscalls

A syscall is accessed via the `rst 48` instruction, which calls a subroutine located at 0x0030 in ROM.
This subroutine uses the A register to perform a lookup into a table of syscall functions, one of which is then executed.
Hence, before executing the `rst` instruction, the A register must be loaded with the value appropriate to look up the desired syscall.
A simple macro is provided to do this:

```
macro   zsyscall, number
ld      A, \number << 1
rst     48
endmacro
```

### Available Syscalls

This section describes the syscalls available to an application running on ZBoot.

----

#### 0: swrite - write character to serial port.

**Parameters**

L holds the byte character to be written to the serial port.

**Return Value**

None.

**Description**

Busy-waits until serial port is ready to transmit,
then writes the given character to the serial port.

----

#### 1: sread - read character from serial port.

**Parameters**

None.

**Return Value**

The character received from the serial port, in A.

**Description**

Busy-waits until serial port receives data,
then returns a single received character.
