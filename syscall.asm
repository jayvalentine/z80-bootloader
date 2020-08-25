    EXTERN  syscall_handler

    ; Syscall entry point. Called using the 'rst 48' instruction.
    org     $0030
syscall_entry:
    jp      syscall_handler 
