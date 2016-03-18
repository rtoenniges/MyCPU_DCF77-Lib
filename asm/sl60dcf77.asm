;[ASCII]
;******************************************
;***********  DCF77 Library  **************
;******************************************
;******  by Robin Tönniges (2016)  ********
;******************************************

#include <sys.hsm>
#include <library.hsm>
#include <code.hsm>
#include <interrupt.hsm>


;-------------------------------------;
; declare variables

;Zeropointer
ZP_temp1        EQU  10h
ZP_temp2        EQU  12h

;Constants
CON_INT         EQU 7   ;IRQ7

;Variables
VAR_second      DB  0   ;Second/Bit counter
VAR_flankcnt    DB  0   ;Flank counter
VAR_synced      DB  1   ;Sync flag -> 0 if synchronized
VAR_dataok      DB  0   ;Parity check -> Bit 1 = Minutes OK, Bit 2 = Hours OK, Bit 3 = Date OK

VAR_minutes     DB  0
VAR_hours       DB  0
VAR_day         DB  0
VAR_weekday     DB  0
VAR_month       DB  0
VAR_year        DB  0
VAR_dateparity  DB  0

VAR_tmpminutes  DB  0
VAR_tmphours    DB  0
VAR_tmpday      DB  0
VAR_tmpweekday  DB  0
VAR_tmpmonth    DB  0

VAR_timerhandle DB  0   ;Address of timerinterrupt-handle

;-------------------------------------;
; begin of assembly code

codestart
#include <library.hsm>

initfunc
;Enable hardware-interrupt (IRQ7)
        LDA  #CON_INT
        LPT  #dcf77
        JSR  (KERN_IC_SETVECTOR)
        JSR  (KERN_IC_ENABLEINT)
        
;Enable timer-interrupt
        CLA    
        LPT  #timer
        JSR  (KERN_MULTIPLEX)
        STAA VAR_timerhandle  ;Adresse des Timer Handlers in Variable speichern

;Initialize zeropage variables
        FLG  ZP_temp1   ;Hardware-interrupt flag
        FLG  ZP_temp1+1 ;Time between two flanks
        FLG  ZP_temp2   ;Temp data
        FLG  ZP_temp2+1 ;Reserve       
        CLA
        RTS
               
termfunc  
        ;Disable timer-interrupt
        LDA  #1
        LDXA VAR_timerhandle      
        JSR (KERN_MULTIPLEX)
        ;Disable hardware-interrupt
        LDA #CON_INT
        JSR (KERN_IC_DISABLEINT)
        RTS
     
funcdispatch
        DEC
        JPZ func_getSeconds     ;Function 01h  
        DEC 
        JPZ func_getMinutes     ;Function 02h         
        DEC 
        JPZ func_getHours       ;Function 03h 
        DEC 
        JPZ func_getDay         ;Function 04h   
        DEC 
        JPZ func_getWeekday     ;Function 05h       
        DEC 
        JPZ func_getMonth       ;Function 06h      
        DEC 
        JPZ func_getYear        ;Function 07h 
        DEC 
        JPZ func_getEntryPoint  ;Function 08h
        JMP _failRTS
        
        
;Function '01h' = Get seconds (OUTPUT = Accu), Carry = 0 if successfull
func_getSeconds
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_second
        JMP _RTS

;Function '02h' = Get minutes (OUTPUT = Accu), Carry = 0 if successfull         
func_getMinutes  
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_minutes
        JMP _RTS
        
;Function '03h' = Get hours (OUTPUT = Accu), Carry = 0 if successfull 
func_getHours
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_hours
        JMP _RTS        
       
;Function '04h' = Get day (OUTPUT = Accu), Carry = 0 if successfull 
func_getDay
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_day
        JMP _RTS    
        
;Function '05h' = Get weekday (OUTPUT = Accu), Carry = 0 if successfull 
;1 = monday, 2 = tuesday, 3 = wednesday, 4 = thursday, 5 = friday, 6 = saturday, 7 = sunday
func_getWeekday
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_weekday
        JMP _RTS   

;Function '06h' = Get month (OUTPUT = Accu), Carry = 0 if successfull 
func_getMonth
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_month
        JMP _RTS     
        
;Function '07h' = Get year (OUTPUT = Accu), Carry = 0 if successfull 
func_getYear
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_year
        JMP _RTS

;Function '08h' = Get entrypoint of library         
func_getEntryPoint
        LPT #funcdispatch
        JMP _RTS

;--------------------------------------------------------- 
;Interrupt routines   
;---------------------------------------------------------       
       
;Receiver interrupt        
dcf77
        MOV ZP_temp1, #1    ;Flank detected -> Set flag
        INCA VAR_flankcnt   ;Count flanks (For signal-error-detection)
        RTS       
        
;Timer interrupt
timer
        LDA ZP_temp1
        JNZ impCtrl       
        ;Measure time between two flanks
        INC ZP_temp1+1
        RTS

;--------------------------------------------------------- 
;DCF77 decoding   
;---------------------------------------------------------

;Mit DCF77-Signal Synchronisieren -> 59. Sekunde ermitteln
impCtrl 
        CLC
        LDA ZP_temp1+1
        SBC #50  
        JNC imp_1
        ;Impulszeit >= 50 -> Länger als 1 Sekunde Pause
;Signal synchron
        CLA 
        STAA VAR_synced
        STAA VAR_second
        STAA VAR_flankcnt
        JMP imp_end
     
;Sekunden zählen, Signal überprüfen   
imp_1   CLC
        LDA ZP_temp1+1
        SBC #20  
        JNC imp_2 ;Impulszeit < 20 -> Nächstes Bit
        ;Impulszeit >= 20 -> Nächste Sekunde
        INCA VAR_second
        ;Signal überpüfen -> Doppelt so viele Flanken wie Sekunden?
        LDAA VAR_flankcnt
        DIV #2
        CMPA VAR_second
        JPZ imp_end
;Nicht mehr synchron oder felerhaftes Signal        
DeSync  LDA #1 
        STAA VAR_synced
        CLA
        STAA VAR_dataok
        JMP imp_end
        
;Datenpakete differenzieren
imp_2   LDAA VAR_second
        CMP #20 ;Beginn der Zeitinformationen = 1
        JNZ imp_3
        LDA ZP_temp1+1
        JSR getBit
        JPZ DeSync ;Bit 20 != 1 -> Nicht mehr synchron oder fehlerhaftes Signal
        JMP imp_end 
 
imp_3   LDAA VAR_synced
        JNZ imp_end
        ;Nur weitermachen wenn synchronisiert
        CLC
        LDAA VAR_second
        SBC #20
        JNC imp_end 
        ;Sekunde >= 21
        CLC
        LDAA VAR_second
        SBC #28
        JNC imp_4 ;Minuten erfassen
        ;Sekunde >= 29
        CLC
        LDAA VAR_second
        SBC #35
        JNC imp_7 ;Stunden erfassen
        ;Sekunde >= 36
        CLC
        LDAA VAR_second
        SBC #41
        JNC imp_10 ;Kalendertag erfassen
        ;Sekunde >= 42
        CLC
        LDAA VAR_second
        SBC #44
        JNC imp_12 ;Wochentag erfassen
        ;Sekunde >= 45
        CLC
        LDAA VAR_second
        SBC #49
        JNC imp_14 ;Monat erfassen
        ;Sekunde >= 50
        CLC
        LDAA VAR_second
        SBC #58
        JNC imp_16 ;Jahr erfassen
        ;Sekunde >= 59
        JMP imp_end

;---------------------------------------------------------

;Minuten erfassen
imp_4   LDAA VAR_second
        CMP #21
        JNZ imp_6
        MOV ZP_temp2, #0

;Hole Bit
imp_6   LDA ZP_temp1+1
        JSR getBit
        PHA
        LDAA VAR_second
        CMP #28
        JPZ imp_5 ;Letze Bit -> Parität
        PLA
        ORA ZP_temp2
        SHR
        STA ZP_temp2
        JMP imp_end

;Parität überprüfen        
imp_5   LDA ZP_temp2  
        LDX #7
        CLY
        JSR bitCnt
        JPC par_0   
        PLA ;Anzahl Bits = "ungerade"
        JNZ par_1
        LDA #1
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_0   PLA ;Anzahl Bits = "gerade"
        JPZ par_1
        LDA #1
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_1   LDA ZP_temp2 ;Parität OK
        JSR bcdToDec
        STAA VAR_tmpminutes
        LDA #1
        ORAA VAR_dataok
        STAA VAR_dataok
        JMP imp_end

    
;Stunden erfassen
imp_7   LDAA VAR_second
        CMP #29
        JNZ imp_9
        MOV ZP_temp2, #0

;Hole Bit
imp_9   LDA ZP_temp1+1
        JSR getBit
        PHA
        LDAA VAR_second
        CMP #35
        JPZ imp_8 ;Letze Bit -> Parität
        PLA
        ORA ZP_temp2
        SHR
        STA ZP_temp2 
        JMP imp_end

;Parität überprüfen         
imp_8   SHR ZP_temp2 ;Letze Bit -> Um 1 nach rechts schieben
        LDA ZP_temp2  
        LDX #6
        CLY
        JSR bitCnt
        JPC par_2   
        PLA ;Anzahl Bits = "ungerade"
        JNZ par_3
        LDA #2
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_2   PLA ;Anzahl Bits = "gerade"
        JPZ par_3
        LDA #2
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_3   LDA ZP_temp2 ;Parität OK
        JSR bcdToDec
        STAA VAR_tmphours
        LDA #2
        ORAA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
        
        
;Kalendertag erfassen
imp_10  LDAA VAR_second
        CMP #36
        JNZ imp_11
        MOV ZP_temp2, #0
  
;Hole Bit      
imp_11  LDA ZP_temp1+1
        JSR getBit
        ORA ZP_temp2
        SHR
        STA ZP_temp2  
      
;High Bits zählen
        LDAA VAR_second
        CMP #41       
        JNZ imp_end 
        SHR ZP_temp2 ;Letze Bit -> Um 1 nach rechts schieben
        LDA ZP_temp2  
        LDX #6
        CLY
        JSR bitCnt
        STAA VAR_dateparity
        LDA ZP_temp2
        JSR bcdToDec
        STAA VAR_tmpday
        JMP imp_end        
        
        
;Wochentag erfassen
imp_12  LDAA VAR_second
        CMP #42
        JNZ imp_13
        MOV ZP_temp2, #0
        
imp_13  LDA ZP_temp1+1
        JSR getBit
        ORA ZP_temp2
        SHR
        STA ZP_temp2       
;High Bits zählen
        LDAA VAR_second
        CMP #44       
        JNZ imp_end 
        ;Um 4 nach rechts schieben
        LDA ZP_temp2 
        DIV #10h
        STA ZP_temp2 
        LDX #3
        LDYA VAR_dateparity
        JSR bitCnt
        STAA VAR_dateparity
        LDA ZP_temp2
        JSR bcdToDec
        STAA VAR_tmpweekday
        JMP imp_end  
        
;Monat erfassen
imp_14  LDAA VAR_second
        CMP #45
        JNZ imp_15
        MOV ZP_temp2, #0
        
;Hole Bit 
imp_15  LDA ZP_temp1+1
        JSR getBit
        ORA ZP_temp2
        SHR
        STA ZP_temp2 
        
;High Bits zählen
        LDAA VAR_second
        CMP #49       
        JNZ imp_end 
        ;Um 2 nach rechts schieben
        SHR ZP_temp2  
        SHR ZP_temp2  
        LDA ZP_temp2  
        LDX #5
        LDYA VAR_dateparity
        JSR bitCnt
        STAA VAR_dateparity
        LDA ZP_temp2
        JSR bcdToDec
        STAA VAR_tmpmonth
        JMP imp_end 
        
;Jahr erfassen
imp_16  LDAA VAR_second
        CMP #50
        JNZ imp_18
        MOV ZP_temp2, #0

;Hole Bit
imp_18  LDA ZP_temp1+1
        JSR getBit
        PHA
        LDAA VAR_second
        CMP #58
        JPZ imp_17 ;Letze Bit -> Parität
        PLA
        ORA ZP_temp2
        SHR
        STA ZP_temp2 
        JMP imp_end

;Parität für das komplette Datum überprüfen         
imp_17  SHL ZP_temp2 ;Letze Bit -> Um 1 nach links schieben
        LDA ZP_temp2
        LDX #8
        LDYA VAR_dateparity
        JSR bitCnt
        JPC par_4   
        PLA ;Anzahl Bits = "ungerade"
        JNZ par_5
        LDA #4
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_4   PLA ;Anzahl Bits = "gerade"
        JPZ par_5
        LDA #4
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_5   LDA ZP_temp2 ;Parität OK
        JSR bcdToDec ;Jahr übernehmen
        STAA VAR_year
        LDAA VAR_tmpminutes ;Minuten übernehmen
        STAA VAR_minutes
        LDAA VAR_tmphours ;Stunden übernehmen
        STAA VAR_hours
        LDAA VAR_tmpday ;Tag übernehmen
        STAA VAR_day
        LDAA VAR_tmpweekday ;Wochentag übernehmen
        STAA VAR_weekday
        LDAA VAR_tmpmonth ;Monat übernehmen
        STAA VAR_month
        LDA #4
        ORAA VAR_dataok
        STAA VAR_dataok
      
;Auf nächste Flanke warten
imp_end
        MOV ZP_temp1, #0
        MOV ZP_temp1+1, #0
        RTS

;--------------------------------------------------------- 
;Hilfsfunktionen   
;---------------------------------------------------------

;Information aus Impulszeit dekodieren (Input: A = Impuzlszähler) (Output: A = High(80h), Low(00h))        
getBit
        CLC       
        SBC #3
        JNC get_0
        ;Impulszeit >= 3 -> Bit = 1
        LDA #80h
        RTS
get_0   CLA ;Impulszeit < 3 -> Bit = 0
        RTS
        
        
;High Bits zählen (Input: A = Byte, X=Anzahl Bits, Y=Zähler offset) (Output: A=Anzahl, C=0 -> Ungerade, C=1 -> Gerade)        
bitCnt
cnt_0   SHR
        JNC cnt_1
        INY
cnt_1   DXJP cnt_0
        SAY
        PHA
        MOD #2
        JPZ cnt_2
        CLC ;Anzahl "ungerade"
        JMP cnt_3
cnt_2   SEC ;Anzahl "gerade"
cnt_3   PLA
        RTS
        
        
;BCD in Dezimal umwandeln (Input: A = BCD-Zahl) (Output: A = Dezimalzahl)       
bcdToDec
        PHA
        DIV #10h
        MUL #0Ah
        STA ZP_temp2
        PLA
        AND #0Fh
        CLC
        ADC ZP_temp2
        STA ZP_temp2
        RTS

_RTS    
        CLC
        RTS
      
_failRTS
        CLA
        SEC
        RTS
        
