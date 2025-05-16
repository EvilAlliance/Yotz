:i argc 0
:b stdin 0

:i returncode 0
:b stdout 96
main :: () u8 { 
    a :: 1000;
    b :: 10;
    c :: (a + 10);
    d: u8 = b;
    return b;
} 

:b stderr 0

