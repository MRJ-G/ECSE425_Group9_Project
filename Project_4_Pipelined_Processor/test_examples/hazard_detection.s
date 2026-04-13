main:
    addi x1, x0, 5
    addi x2, x1, 3
    addi x3, x2, 4
    add  x4, x3, x1
    addi x5, x4, 1
stop:
    j stop
