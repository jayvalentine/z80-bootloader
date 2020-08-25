    EXTERN  breakpoint_handler

    ; Debug breakpoint handler.
    org     $0028
breakpoint_entry:
    jp      breakpoint_handler
