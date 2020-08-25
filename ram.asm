    org     $f000
system_ram:
rx_buf:
    defs    $100
rx_buf_head:
    defs    1
rx_buf_tail:
    defs    1
ihex_record:
    defs    44
ihex_record_end:
prompt_input:
    defs    64
cmd:
    defs    16
argv:
    defs    64
breakpoint:
    defs    1

    ; Export the labels publicly.
    PUBLIC  rx_buf
    PUBLIC  rx_buf_head
    PUBLIC  rx_buf_tail
    PUBLIC  ihex_record
    PUBLIC  ihex_record_end
    PUBLIC  prompt_input
    PUBLIC  cmd
    PUBLIC  argv
    PUBLIC  breakpoint
