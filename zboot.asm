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
    call    gets
    cp      A, 's'
    jp      nz, _main_loop

    ld      HL, serial_load_message
    call    print

    ; Receive size of data in big-endian format.
    call    gets
    ld      D, A
    call    gets
    ld      E, A

    ; Loop.
    ld      HL, $8000
receive_data:
    call    gets

    ld      (HL), A
    inc     HL

    dec     DE
    ld      A, E
    or      D
    jp      z, receive_data_done

    jp      receive_data

receive_data_done:
    ld      HL, received_message
    call    print

    ; Execute loaded program.
    jp      $8000

    halt

puts:
    ; Wait for ready to send.
    in      A, (UART_PORT_CONTROL)
    bit     1, A
    jp      z, puts

    out     (UART_PORT_DATA), A
    ret

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

gets:
    in      A, (UART_PORT_CONTROL)
    bit     0, A
    jp      z, gets

    ; Now ready to receive byte.
    in      A, (UART_PORT_DATA)
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
boot_message_end:

serial_load_message:
    text    "Waiting for serial transfer..."
    byte    CR, LF
    byte    $00
serial_load_message_end:

received_message:
    text    "Data received:"
    byte    CR, LF
    byte    $00
received_message_end:
