main:
    addi x1, x0, 5
    addi x2, x0, 7
    nop
    nop
    add  x3, x1, x2
    nop
    nop
    sw   x3, 0(x0)
    nop
    nop
    lw   x4, 0(x0)
stop:
    j stop
