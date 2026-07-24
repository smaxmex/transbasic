REM ========================================================
REM Trans BASIC (tb) - Versione CLI (Riga di Comando)
REM ========================================================

REM Trappola globale per gli errori: stampa l'errore ed esce sempre alla shell
ON ERROR PROC_printCLI("ERRORE BASIC: " + REPORT$) : QUIT

REM Nasconde immediatamente la finestra grafica di BBC BASIC se aperta
ON ERROR LOCAL GOTO (salta_nascondi)
SYS "SDL_HideWindow", @hwnd%
(salta_nascondi)

DIM uk$(1000), tr$(1000)
numKw% = 0

fIn$ = ""
fDict$ = ""
dir% = 0
noExec% = FALSE

REM Legge gli argomenti dalla riga di comando (@cmd$)
PROC_parseCLI(@cmd$, fIn$, fDict$, dir%, noExec%)

REM Se non ci sono argomenti, mostra l'aiuto ed esce
IF fIn$ = "" THEN
  PROC_printCLI("tb (Trans BASIC) - Derivato da BBC BASIC for SDL")
  PROC_printCLI("Traduce codice sorgente da e verso BASIC in altre lingue.")
  PROC_printCLI("")
  PROC_printCLI("Uso: ./tb <sorgente.bas> [dizionario.txt] [-c | -t] [-ne]")
  PROC_printCLI("  -c  : BASIC in altra lingua -> BASIC in inglese (predefinito).")
  PROC_printCLI("        Crea anche il file tokenizzato .bbc e l'eseguibile concatenando bbcsdl e .bbc")
  PROC_printCLI("        e lo manda in esecuzione.")
  PROC_printCLI("  -ne : Non esegue l'eseguibile creato con l'opzione -c.")
  PROC_printCLI("  -t  : BASIC in inglese -> BASIC in altra lingua")
  PROC_printCLI("")
  PROC_printCLI("Nota: Se omesso, il dizionario predefinito e' 'basilico.txt'")
  PROC_printCLI("      (utilizzato per il BASIC in italiano).")
  QUIT
ENDIF

IF fDict$ = "" THEN fDict$ = "basilico.txt"
IF dir% <> 1 AND dir% <> 2 THEN dir% = 2

PROC_loadDict(fDict$)

REM Generazione nomi file di output (.out.bas, .bbc, eseguibile)
p% = INSTR(FN_UPR(fIn$), ".BAS")

IF p% > 0 THEN
  base$ = LEFT$(fIn$, p% - 1)
ELSE
  base$ = fIn$
ENDIF

fOut$ = base$ + ".out.bas"
fBbc$ = base$ + ".bbc"
fExe$ = base$

PROC_printCLI("Traduzione di """ + fIn$ + """ in corso...")
PROC_translate(fIn$, fOut$, dir%)
PROC_printCLI("Creato sorgente tradotto: """ + fOut$ + """")

REM Generazione file .bbc ed eseguibile SOLO con opzione -c (dir% = 2)
IF dir% = 2 THEN
  PROC_makeExecutable(fOut$, fBbc$, fExe$)
  
  REM Manda in esecuzione se non c'è l'opzione -ne
  IF NOT noExec% THEN
    PROC_printCLI("Avvio di """ + fExe$ + """...")
    REM Le virgolette garantiscono l'avvio corretto in caso di spazi nel nome
    SYS "system", "./""" + fExe$ + """"
  ELSE
    PROC_printCLI("Esecuzione saltata (rilevata opzione -ne).")
  ENDIF
ENDIF

PROC_printCLI("Operazione completata!")
QUIT

REM ========================================================
REM GENERAZIONE FILE .BBC ED ESEGUIBILE LINUX
REM ========================================================
DEF PROC_makeExecutable(fOut$, fBbc$, fExe$)
LOCAL cmd$, F%

PROC_printCLI("Generazione file tokenizzato """ + fBbc$ + """...")

REM 1. Usa ./bbcbasic (CLI) via pipe per tokenizzare il sorgente senza interfaccia grafica
cmd$ = "printf 'LOAD """ + fOut$ + """\nSAVE """ + fBbc$ + """\nQUIT\n' | ./bbcbasic >/dev/null 2>&1; "

REM 2. Concatena l'interprete grafico ./bbcsdl al file .bbc e imposta i permessi di esecuzione
cmd$ = cmd$ + "cat ./bbcsdl """ + fBbc$ + """ > """ + fExe$ + """ 2>/dev/null && chmod +x """ + fExe$ + """"

SYS "system", cmd$

REM Verifica la creazione del file .bbc
F% = OPENIN(fBbc$)
IF F% = 0 THEN
  PROC_printCLI("AVVISO: Impossibile generare """ + fBbc$ + """. Assicurati che './bbcbasic' sia presente ed eseguibile.")
ELSE
  CLOSE#F%
  PROC_printCLI("Creato file tokenizzato: """ + fBbc$ + """")
  PROC_printCLI("Creato eseguibile finale: """ + fExe$ + """")
ENDIF
ENDPROC

REM ========================================================
REM STAMPA DIRETTAMENTE SU STDOUT (TERMINALE LINUX / CLI)
REM ========================================================
DEF PROC_printCLI(msg$)
LOCAL hStdOut%, written%

REM 1. Prova API Windows
ON ERROR LOCAL GOTO (prova_printf)
SYS "GetStdHandle", -11 TO hStdOut%
IF hStdOut% <> 0 AND hStdOut% <> -1 THEN
  SYS "WriteFile", hStdOut%, msg$ + CHR$(13) + CHR$(10), LEN(msg$) + 2, ^written%, 0
  ENDPROC
ENDIF

(prova_printf)
REM 2. Libreria C 'printf' su Linux
ON ERROR LOCAL GOTO (stampa_emergenza)
SYS "printf", "%s" + CHR$(13) + CHR$(10), msg$
SYS "fflush", 0
ENDPROC

(stampa_emergenza)
PRINT msg$
ENDPROC

REM ========================================================
REM PARSING RIGA DI COMANDO (A PROVA DI SPAZI)
REM ========================================================
DEF PROC_parseCLI(cmd$, RETURN in$, RETURN dict$, RETURN d%, RETURN ne%)
LOCAL F%, a$, count%, p%
count% = 0

REM --- METODO 1: Lettura nativa da Linux (Infallibile per gli spazi) ---
ON ERROR LOCAL GOTO (metodo_testo)
F% = OPENIN("/proc/self/cmdline")
IF F% <> 0 THEN
  a$ = FN_readNullString(F%) : REM Ignora argv[0] (il comando eseguito)
  WHILE NOT EOF#F%
    a$ = FN_readNullString(F%)
    IF a$ <> "" THEN
      REM Ignora l'eseguibile script .bbc se e' il primo parametro passato dall'interprete
      IF RIGHT$(FN_UPR(a$), 4) = ".BBC" AND count% = 0 THEN
        REM Salta
      ELSE
        IF FN_UPR(a$) = "-C" THEN
          d% = 2
        ELSE
          IF FN_UPR(a$) = "-T" THEN
            d% = 1
          ELSE
            IF FN_UPR(a$) = "-NE" THEN
              ne% = TRUE
            ELSE
              REM Tutto ciò che non è opzione è un file
              count% = count% + 1
              IF count% = 1 THEN in$ = a$
              IF count% = 2 THEN dict$ = a$
            ENDIF
          ENDIF
        ENDIF
      ENDIF
    ENDIF
  ENDWHILE
  CLOSE#F%
  
  REM Se il file è stato trovato con questo metodo, esci
  IF in$ <> "" THEN ENDPROC
ENDIF

(metodo_testo)
REM --- METODO 2: Fallback tramite estensioni ---
REM Se /proc/ non è disponibile, estrae i nomi in base all'estensione
cmd$ = FN_trim(cmd$)

REM Estrae il file .bas (sorgente)
p% = INSTR(FN_UPR(cmd$), ".BAS")
IF p% > 0 THEN
  in$ = FN_trim(LEFT$(cmd$, p% + 3))
  cmd$ = FN_trim(MID$(cmd$, p% + 4))
  in$ = FN_unquote(in$)
ENDIF

REM Estrae l'eventuale file .txt (dizionario)
p% = INSTR(FN_UPR(cmd$), ".TXT")
IF p% > 0 THEN
  dict$ = FN_trim(LEFT$(cmd$, p% + 3))
  cmd$ = FN_trim(MID$(cmd$, p% + 4))
  dict$ = FN_unquote(dict$)
ENDIF

REM Applica le opzioni presenti
IF INSTR(FN_UPR(cmd$), "-C") > 0 THEN d% = 2
IF INSTR(FN_UPR(cmd$), "-T") > 0 THEN d% = 1
IF INSTR(FN_UPR(cmd$), "-NE") > 0 THEN ne% = TRUE
ENDPROC

DEF FN_readNullString(F%)
LOCAL s$, c%
s$ = ""
WHILE NOT EOF#F%
  c% = BGET#F%
  IF c% = 0 THEN = s$
  s$ = s$ + CHR$(c%)
ENDWHILE
= s$

DEF FN_unquote(s$)
IF LEFT$(s$, 1) = """" THEN s$ = MID$(s$, 2)
IF RIGHT$(s$, 1) = """" THEN s$ = LEFT$(s$, LEN(s$) - 1)
= s$

DEF FN_trim(s$)
WHILE LEFT$(s$, 1) = " " : s$ = MID$(s$, 2) : ENDWHILE
WHILE RIGHT$(s$, 1) = " " : s$ = LEFT$(s$, LEN(s$) - 1) : ENDWHILE
= s$

REM ========================================================
REM CARICAMENTO DIZIONARIO
REM ========================================================
DEF PROC_loadDict(f$)
LOCAL F%, L$, p%
F% = OPENIN(f$)
IF F% = 0 THEN
  PROC_printCLI("ERRORE: Dizionario """ + f$ + """ non trovato!")
  QUIT
ENDIF
WHILE NOT EOF#F%
  L$ = FN_readLine(F%)
  p% = INSTR(L$, ",")
  IF p% > 0 THEN
    numKw% = numKw% + 1
    uk$(numKw%) = FN_UPR(LEFT$(L$, p% - 1))
    tr$(numKw%) = FN_UPR(MID$(L$, p% + 1))
  ENDIF
ENDWHILE
CLOSE#F%
PROC_printCLI("Caricate " + STR$(numKw%) + " parole chiave dal dizionario.")
ENDPROC

REM ========================================================
REM MOTORE DI TRADUZIONE
REM ========================================================
DEF PROC_translate(in$, out$, dir%)
LOCAL fI%, fO%, L$, T$
fI% = OPENIN(in$)
IF fI% = 0 THEN
  PROC_printCLI("ERRORE: Sorgente """ + in$ + """ non trovato!")
  QUIT
ENDIF
fO% = OPENOUT(out$)
IF fO% = 0 THEN
  PROC_printCLI("ERRORE: Impossibile scrivere su """ + out$ + """")
  CLOSE#fI%
  QUIT
ENDIF

WHILE NOT EOF#fI%
  L$ = FN_readLine(fI%)
  T$ = FN_trans(L$, dir%)
  PROC_writeLine(fO%, T$)
ENDWHILE

CLOSE#fI%
CLOSE#fO%
ENDPROC

DEF FN_trans(L$, dir%)
LOCAL res$, i%, c$, inQ%, word$, transWord$
inQ% = FALSE
i% = 1
res$ = ""
WHILE i% <= LEN(L$)
  c$ = MID$(L$, i%, 1)
  IF c$ = """" THEN
    inQ% = NOT inQ%
    res$ = res$ + c$
    i% = i% + 1
  ELSE
    IF inQ% THEN
      res$ = res$ + c$
      i% = i% + 1
    ELSE
      IF FN_isAlpha(c$) THEN
        word$ = ""
        WHILE i% <= LEN(L$) AND FN_isAlnum(MID$(L$, i%, 1))
          word$ = word$ + MID$(L$, i%, 1)
          i% = i% + 1
        ENDWHILE
        transWord$ = FN_lookup(word$, dir%)
        res$ = res$ + transWord$
        
        IF (FN_UPR(transWord$) = "REM" OR FN_UPR(transWord$) = "DATA") THEN
          IF i% <= LEN(L$) THEN res$ = res$ + MID$(L$, i%)
          i% = LEN(L$) + 1
        ENDIF
      ELSE
        res$ = res$ + c$
        i% = i% + 1
      ENDIF
    ENDIF
  ENDIF
ENDWHILE
= res$

DEF FN_lookup(w$, dir%)
LOCAL j%, u$, found$
u$ = FN_UPR(w$)
found$ = w$
FOR j% = 1 TO numKw%
  IF dir% = 1 AND uk$(j%) = u$ THEN found$ = tr$(j%)
  IF dir% = 2 AND FN_UPR(tr$(j%)) = u$ THEN found$ = uk$(j%)
NEXT j%
= found$

REM ========================================================
REM UTILITY FILE E TESTO
REM ========================================================
DEF FN_readLine(F%)
LOCAL L$, c%
L$ = ""
WHILE NOT EOF#F%
  c% = BGET#F%
  IF c% = 10 THEN = L$
  IF c% <> 13 THEN L$ = L$ + CHR$(c%)
ENDWHILE
= L$

DEF PROC_writeLine(F%, L$)
LOCAL i%
IF LEN(L$) > 0 THEN
  FOR i% = 1 TO LEN(L$)
    BPUT#F%, ASC(MID$(L$, i%, 1))
  NEXT i%
ENDIF
BPUT#F%, 10
ENDPROC

DEF FN_isAlpha(c$)
= (c$ >= "A" AND c$ <= "Z") OR (c$ >= "a" AND c$ <= "z") OR (c$ = "_")

DEF FN_isAlnum(c$)
= FN_isAlpha(c$) OR (c$ >= "0" AND c$ <= "9") OR (c$ = "$") OR (c$ = "%") OR (c$ = "#")

DEF FN_UPR(a$)
LOCAL i%, c%, r$
r$ = ""
IF LEN(a$) = 0 THEN = ""
FOR i% = 1 TO LEN(a$)
  c% = ASC(MID$(a$, i%, 1))
  IF c% >= 97 AND c% <= 122 THEN
    r$ = r$ + CHR$(c% - 32)
  ELSE
    r$ = r$ + CHR$(c%)
  ENDIF
NEXT i%
= r$

