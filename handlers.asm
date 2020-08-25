    EXTERN  breakpoint
    EXTERN  syscall_table

breakpoint_handler:
    ; Store HL on stack, get stack top (return address)
    ; in HL.
    ex      (SP), HL

    push    HL
    push    AF
    pop     AF
    pop     HL

    ; Return address is address of breakpoint +1.
    dec     HL

    ; Restore original instruction.
    ld      A, (breakpoint)
    ld      (HL), A

    ; Restore HL.
    ex      (SP), HL

    ; Re-execute replaced instruction.
    ret

syscall_handler:
    push    HL
    push    DE
    ld      DE, syscall_table
    ld      E, A
    
    ld      A, (DE)
    ld      L, A
    inc     DE

    ld      A, (DE)
    ld      H, A
    
    jp      (HL)

    PUBLIC  breakpoint_handler
    PUBLIC  syscall_handler
