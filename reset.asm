    EXTERN  start
    EXTERN  breakpoint_handler
    EXTERN  syscall_handler
    EXTERN  interrupt_handler
    
    ; Entry point.
    org     0x0000
reset:
    ; Disable interrupts on startup.
    di
    jp      start

    defs    0x0028 - ASMPC
breakpoint_entry:
    jp      breakpoint_handler

    defs    0x0030 - ASMPC
syscall_entry:
    jp      syscall_handler

    defs    0x0038 - ASMPC
interrupt_entry:
    jp      interrupt_handler

    ; Buffer space to 0x0100.
    defs    0x0100 - ASMPC
