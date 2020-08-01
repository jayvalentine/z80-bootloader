    ; ZBoot, a Z80 Bootloader.
    ; Copyright (c) 2020 Jay Valentine

    ; Character definitions
CR                  = $0d
LF                  = $0a

    ; Symbol definitions
UART_PORT_DATA      = 0b00000001
UART_PORT_CONTROL   = 0b00000000

    ; Program reset vector.
    org     $0000
reset:
    jp      start

    ; Startup code.
    org     $0100
start:
    ; Initialize stack pointer.
    ld      SP, $ffff

    ; Initialize UART.

    ; Master reset.
    ld      A, 0b00000011
    out     (UART_PORT_CONTROL), A

    ; Configure UART.
    ; UART will run at 57600baud with a 3.6864MHz clock.
    ; Word length of 8 bits + 1 stop.
    ; Interrupts disabled.
    ld      A, 0b00010110
    out     (UART_PORT_CONTROL), A

main:
    ld      HL, boot_message
    call    print

_main_loop:
    call    getchar
    cp      A, 's'
    jp      nz, _main_loop

    ld      HL, serial_load_message
    call    print

receive_data:
    call    get_ihex_record

    cp      A, $00
    jp      nz, receive_data

    ld      HL, received_message
    call    print

    ; Execute loaded program.
    ld      HL, $8000
    call    print

    halt

print:
    ; Short-circuit in the case where we're given just
    ; a null-byte.
    ld      A, (HL)
    cp      $00
    jp      z, _print_done

_print_loop:
    ; Wait for ready to send.
    in      A, (UART_PORT_CONTROL)
    bit     1, A
    jp      z, _print_loop

    ; Send a character
    ld      A, (HL)
    cp      $00
    jp      z, _print_done

    inc     HL
    out     (UART_PORT_DATA), A

    jp      _print_loop

_print_done:
    ret

wait_uart_ready:
    ; Wait for ready to send.
    in      A, (UART_PORT_CONTROL)
    bit     1, A
    jp      z, wait_uart_ready
    ret

getchar:
    in      A, (UART_PORT_CONTROL)
    bit     0, A
    jp      z, getchar

    ; Now ready to receive byte.
    in      A, (UART_PORT_DATA)
    ret

get_ihex_record:
    push    HL
    push    BC

    ; Get a character and echo.
    call    getchar
    out     (UART_PORT_DATA), A

    ; Expect first character of a record to be ':'
    cp      ':'
    jp      nz, _get_ihex_record_invalid

    call    wait_uart_ready

    ; Load size of record data into B.
    call    getbyte
    ld      B, A

    call    wait_uart_ready

    ; Next is address, in HL.
    call    getbyte
    ld      H, A
    call    getbyte
    ld      L, A

    call    wait_uart_ready

    ; Now record type.
    ; If we assume we're only handling type 0 and 1 records then we don't need to
    ; actually parse the byte.
    call    getchar
    out     (UART_PORT_DATA), A
    call    getchar
    out     (UART_PORT_DATA), A

    cp      '0'
    jp      z, _get_ihex_record_isdata

    call    wait_uart_ready

    ; Get checksum, but don't do anything with it.
    call    getchar
    out     (UART_PORT_DATA), A
    call    getchar
    out     (UART_PORT_DATA), A

    ; LF (add CR)
    call    getchar
    out     (UART_PORT_DATA), A

    call    wait_uart_ready

    ld      A, CR
    out     (UART_PORT_DATA), A

    ; End record. We're done, so return false.
    ld      A, $00
    jp      _get_ihex_done

_get_ihex_record_isdata:
    call    wait_uart_ready

    ; Get a byte and store at address in HL.
    ; Then increment HL and loop until B is 0.
    call    getbyte
    ld      (HL), A
    inc     HL
    djnz    _get_ihex_record_isdata

    call    wait_uart_ready

    ; Get checksum, but don't do anything with it.
    call    getchar
    out     (UART_PORT_DATA), A
    call    getchar
    out     (UART_PORT_DATA), A

    ; LF (add CR)
    call    getchar
    out     (UART_PORT_DATA), A

    call    wait_uart_ready

    ld      A, CR
    out     (UART_PORT_DATA), A

    ; We've processed data, so another record is required.
    ; Return true.
    ld      A, $01
    jp      _get_ihex_done

_get_ihex_record_invalid:
    ld      HL, record_invalid_message
    call    print
    ld      A, $00

_get_ihex_done:
    pop     BC
    pop     HL
    ret

getbyte:
    push    BC

    call    getchar
    out     (UART_PORT_DATA), A
    ld      B, A

    call    getchar
    out     (UART_PORT_DATA), A
    ld      C, A

    call    hexconvert

    pop     BC
    ret

hexconvert:
    ; First handle the lower half.
    ld      A, C
    call    _hexconvert_sub_getnybble
    ld      C, A

    ; Now handle the upper half. Shift left 4 times
    ; and then OR in the value of the lower half.
    ld      A, B
    call    _hexconvert_sub_getnybble
    sla     A
    sla     A
    sla     A
    sla     A
    or      C

    ret

    ; Helper subroutine. Assumes hex character in A register,
    ; returns that character's value in A.
_hexconvert_sub_getnybble:
    ; Is it a decimal digit?
    cp      ':'
    jp      nc, _hexconvert_sub_isuppercase

    sub     $30
    ret

_hexconvert_sub_isuppercase:
    ; Is it uppercase char?
    cp      'G'
    jp      nc, _hexconvert_sub_islowercase

    sub     $37
    ret

_hexconvert_sub_islowercase:
    ; Let's assume it's lowercase at this point.
    sub     $57
    ret

boot_message:
    text    "ZBoot, a Z80 bootloader/monitor."
    byte    CR, LF
    
    text    "Copyright (c) 2020 Jay Valentine."
    byte    CR, LF
    
    byte    CR, LF

    text    "Select one of the following options:"
    byte    CR, LF

    byte    CR, LF

    text    "(s)erial boot"
    byte    CR, LF

    byte    $00

serial_load_message:
    text    "Waiting for serial transfer..."
    byte    CR, LF
    byte    $00

received_message:
    text    "Data received:"
    byte    CR, LF
    byte    $00

record_invalid_message:
    text    "Invalid Intel-HEX record."
    byte    CR, LF
    byte    $00
