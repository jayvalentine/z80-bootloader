    EXTERN  UART_PORT_DATA
    
    EXTERN  rx_buf_tail

    ; Interrupt handler.
    org     $0038
interrupt_entry:
    di
    push    HL
    push    AF

    ; Get current tail of buffer.
    ld      H, $f0
    ld      A, (rx_buf_tail)
    ld      L, A

    ; Read data from UART.
    in      A, (UART_PORT_DATA)

    ; Store received character.
    ld      (HL), A

    ; Increment tail.
    ld      HL, rx_buf_tail
    inc     (HL)

    pop     AF
    pop     HL
    ei
    reti
