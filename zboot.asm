    ; ZBoot, a Z80 Bootloader.
    ; Copyright (c) 2020 Jay Valentine

    ; Character definitions
CR                  = $0d
LF                  = $0a
NULL                = $00

    ; Symbol definitions
UART_PORT_DATA      = 0b00000001
UART_PORT_CONTROL   = 0b00000000

SYSTEM_RAM_START    = $f000
IHEX_RECORD         = SYSTEM_RAM_START
IHEX_RECORD_END     = IHEX_RECORD+44    ; Assuming a maximum of 16 data bytes for a record.
                                        ; From observation, this seems valid.
                                        ; Reserve an extra character for NULL.

PROMPT_CMD          = IHEX_RECORD_END
PROMPT_CMD_END      = PROMPT_CMD+16

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

_main_prompt_loop:
    ld      HL, prompt
    call    print

    ld      HL, PROMPT_CMD
    call    getline

    call    wait_uart_ready
    ld      A, CR
    out     (UART_PORT_DATA), A
    call    wait_uart_ready
    ld      A, LF
    out     (UART_PORT_DATA), A

    ld      B, (monitor_commands_end-monitor_commands)/2
    ld      HL, monitor_commands
_main_prompt_parse_loop:
    ; Load command address in little-endian format.
    ld      E, (HL)
    inc     HL
    ld      D, (HL)
    inc     HL

    ; DE now holds address of command, plus command string.
    ; Save HL and load the command subroutine address into it.
    push    HL

    ld      A, (DE)
    ld      L, A
    inc     DE

    ld      A, (DE)
    ld      H, A
    inc     DE

    ; DE now holds address of string with which to make comparison.

    ; Save command subroutine address.
    push    HL

    ; Compare the string, pointed to by DE,
    ; with the command we got from user, in PROMPT_CMD.
    ld      HL, PROMPT_CMD
_prompt_command_compare:
    ld      C, (HL)
    ld      A, (DE)

    inc     HL
    inc     DE

    cp      C
    jp      nz, _prompt_command_next

    ; If A is null, we've got to the end of both
    ; strings and not found any differences.
    cp      NULL
    jp      z, _prompt_command_found

    ; Check next character.
    jp      _prompt_command_compare

_prompt_command_next:
    ; Discard subroutine address and restore command address.
    pop     HL
    pop     HL ; Command address.

    djnz    _main_prompt_parse_loop
    
    ; Exhausted list and not found command.
    ld      HL, command_not_found_message
    call    print
    jp      _main_prompt_loop

_prompt_command_found:
    ; Restore subroutine address and execute.
    pop     HL
    jp      (HL)

_prompt_command_ret:
    ; Discard command search address and jump
    ; back to prompt.
    pop     HL
    jp      _main_prompt_loop

    halt
    
cmd_sub_load:
    ld      HL, serial_load_message
    call    print

_cmd_sub_load_data:
    call    get_ihex_record

    cp      A, $00
    jp      nz, _cmd_sub_load_data

    ld      HL, received_message
    call    print
    jp      _prompt_command_ret

cmd_sub_exec:
    call    $8000
    jp      _prompt_command_ret

    ; Gets a CR/LF-terminated line from serial port.
    ; Destination address is in HL.
getline:
    push    HL

_getline_skip_whitespace
    call    getchar
    cp      CR
    jp      z, _getline_skip_whitespace
    cp      LF
    jp      z, _getline_skip_whitespace

    ; We now have our first valid character in A.
_getline_characters:
    out     (UART_PORT_DATA), A ; Echo.
    ld      (HL), A
    inc     HL

    call    getchar
    
    cp      CR
    jp      z, _getline_done
    cp      LF
    jp      z, _getline_done

    jp      _getline_characters

    ; Full line now in buffer.
    ; Let's reset our pointer to the start.
_getline_done:
    ; Write terminating null.
    ld      (HL), NULL

    pop     HL
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
    push    DE
    push    HL
    push    BC

    ; Zero the record string.
    ld      HL, IHEX_RECORD
    ld      B, IHEX_RECORD_END-IHEX_RECORD
_get_ihex_zero:
    ld      (HL), NULL
    inc     HL
    djnz    _get_ihex_zero

    ; Get a CR/LF-delimited record.
    ld      HL, IHEX_RECORD
    call    getline

    ; Get a character and echo.
    call    _ihex_sub_getchar

    ; Expect first character of a record to be ':'
    cp      ':'
    jp      nz, _get_ihex_record_invalid

    ; Load size of record data into B.
    call    _ihex_sub_getbyte
    ld      B, A

    ; Next is address, in DE.
    call    _ihex_sub_getbyte
    ld      D, A
    call    _ihex_sub_getbyte
    ld      E, A

    ; Now record type. We only handle the following record types currently:
    ; 00 - Data record
    ; 01 - End of file record
    ;
    ; Seeing as this is a 16-bit address space we're unlikely to need the others.
    call    _ihex_sub_getbyte
    cp      0
    jp      z, _get_ihex_record_isdata

    call    wait_uart_ready

    ; Get checksum, but don't do anything with it.
    call    _ihex_sub_getbyte

    ; Print CRLF
    call    wait_uart_ready
    ld      A, CR
    out     (UART_PORT_DATA), A
    call    wait_uart_ready
    ld      A, LF
    out     (UART_PORT_DATA), A

    ; End record. We're done, so return false.
    ld      A, $00
    jp      _get_ihex_done

_get_ihex_record_isdata:
    ; Get a byte and store at address in DE.
    ; Then increment DE and loop until B is 0.
    call    _ihex_sub_getbyte
    ld      (DE), A
    inc     DE
    djnz    _get_ihex_record_isdata

    ; Get checksum, but don't do anything with it.
    call    _ihex_sub_getbyte

    ; Print CRLF
    call    wait_uart_ready
    ld      A, CR
    out     (UART_PORT_DATA), A
    call    wait_uart_ready
    ld      A, LF
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
    pop     DE
    ret

_ihex_sub_getchar:
    ld      A, (HL)
    cp      0
    jp      nz, _ihex_sub_getchar_okay

    ; Change return address to error handler.
    pop     HL
    ld      HL, _get_ihex_record_invalid
    push    HL
    ret

_ihex_sub_getchar_okay:
    inc     HL
    ret

_ihex_sub_getbyte:
    push    BC

    call    _ihex_sub_getchar
    ld      B, A

    call    _ihex_sub_getchar
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

prompt:
    text    "> "
    byte    NULL

command_not_found_message:
    text    "Command not found."
    byte    CR, LF, NULL

    ; Command table for the monitor.
monitor_commands:
    addr    cmd_load
    addr    cmd_exec
monitor_commands_end:

cmd_load:
    addr    cmd_sub_load
    text    "load"
    byte    NULL
cmd_exec:
    addr    cmd_sub_exec
    text    "exec"
    byte    NULL

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
