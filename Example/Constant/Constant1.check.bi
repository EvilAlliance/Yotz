:i argc 0
:b stdin 0

:i returncode 0
:b stdout 120
main :: () u8 { 
    a: u16, u8 : 10;
    b: u16, u8 : (20 + a);
    c: u16 = a;
    d: u16 = b;
    return (a + b);
} 

:b stderr 0

