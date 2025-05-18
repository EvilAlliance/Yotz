:i argc 0
:b stdin 0

:i returncode 0
:b stdout 62
main :: () u8 { 
    a := 8;
    b: u16 = a;
    return a;
} 

:b stderr 134
Example/Inference/Inference2.yt:2:5 [ERROR]: Found this variable used in 2 different contexts (ambiguous typing) 
     a := 8;
     ^

