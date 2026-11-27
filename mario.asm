; Super Mario Engine     
; params are pushed left to right, last one is at [bp+4], callee cleans with ret 2*n
; ---------------- constants (EQU) ----------------
SCRW        equ 320                 ; screen width / height in pixels
SCRH        equ 200
MAPPX       equ 192                 ; map height in pixels (12 rows, rest is black)
TILE        equ 16                  ; tile / sprite size
TILESHIFT   equ 4                   ; log2(TILE)
MAPW        equ 60                  ; level width in tiles
MAPSIZE     equ 720                 ; 60 x 12 tiles
LEVELPX     equ 960                 ; level width in pixels
MAXCAM      equ 640                 ; last camera position (LEVELPX - 320)
CAMFOLLOW   equ 160                 ; camera follows Mario past this screen x
VISCOLS     equ 21                  ; 20 columns + 1 partial
; colours (default VGA palette)
C_BLACK     equ 0
C_GREEN     equ 2
C_RED       equ 4
C_BROWN     equ 6
C_LGRAY     equ 7
C_DGRAY     equ 8
C_SKY       equ 9
C_LGREEN    equ 10
C_YELLOW    equ 14
C_WHITE     equ 15
; scan codes
SC_ESC      equ 0x01
SC_LSHIFT   equ 0x2A
SC_ENTER    equ 0x1C
SC_P        equ 0x19
SC_SPACE    equ 0x39
SC_UP       equ 0x48
SC_LEFT     equ 0x4B
SC_RIGHT    equ 0x4D
SC_DOWN     equ 0x50
; game states
ST_TITLE    equ 0
ST_PLAYING  equ 1
ST_PAUSED   equ 2
ST_DYING    equ 3
ST_LIFELOST equ 4
ST_WIN      equ 5
ST_COMPLETE equ 6
ST_GAMEOVER equ 7
ST_EXIT     equ 8
; tile codes
T_SKY       equ 0
T_GROUND    equ 1
T_BRICK     equ 2
T_QCOIN     equ 3
T_QMUSH     equ 4
T_EMPTY     equ 5
T_LASTSOLID equ 10
T_COIN      equ 11
T_POLE      equ 12
; physics, 8.8 fixed point, 30 frames per second
WALKACC     equ 0x0040
BRAKEACC    equ 0x0080
FRICTION    equ 0x0020
WALKMAX     equ 0x0280
RUNMAX      equ 0x0480
GRAVITY     equ 0x0040
MAXFALL     equ 0x0400
JUMPV       equ 0xFA80              ; -5.5
JUMPCUT     equ 0xFE00              ; -2.0
BOUNCE      equ 0xFD00              ; -3.0
BOUNCEHI    equ 0xFB00              ; -5.0 (jump key held)
DEATHHOP    equ 0xFB20              ; about 48 pixels up
; game limits
STARTLIVES  equ 3
MAXLIVES    equ 99
LEVELTIME   equ 300
COINSFORLIFE equ 100
MAXSCOREHI  equ 0x000F              ; 999999 = 0x000F423F
MAXSCORELO  equ 0x423F
TICKSEC     equ 30                  ; timer ticks per second
INVULNFRAMES equ 60                 ; 2 s
FLATFRAMES  equ 30                  ; 1 s
GRACEFRAMES equ 8                   ; shell kick grace
DEATHFRAMES equ 45                  ; 1.5 s
LIFELOSTFRAMES equ 60               ; 2 s
PITLO       equ 0x5D                ; timer divisor 39773 = 30 Hz
PITHI       equ 0x9B

[org 0x0100]
        jmp start

; ---------------- data ----------------
bufseg:     dw 0                    ; off-screen buffer segment
oldkb:      dd 0
oldtimer:   dd 0
keys:       times 128 db 0          ; 1 = key held
kbpress:    db 0                    ; last key pressed (one shot)
ticks:      dw 0
lasttick:   dw 0
delta:      dw 1
acc:        db 0
frame:      db 0
state:      db ST_TITLE
menusel:    db 0
tickcount:  dw 0
timeleft:   dw 300
endtime:    dw 0
wintimer:   dw 0
winphase:   db 0
dytimer:    dw 0
lltimer:    dw 0
flagtouch:  db 0

mx:         dw 32                   ; world x, y in pixels + fraction byte
mxf:        db 0
my:         dw 144
myf:        db 0
mvx:        dw 0                    ; 8.8 fixed point
mvy:        dw 0
mh:         dw 16                   ; hitbox height 16 or 32
facing:     db 0
onground:   db 0
jumplock:   db 0
form:       db 0                    ; 0 small 1 super
hp:         db 1
chain:      db 0
invuln:     dw 0
camerax:    dw 0
score:      dd 0
coins:      db 0
lives:      db 3
numbuf:     times 8 db 0

chaintable: dw 100,200,400,500,800,1000,2000,4000,5000,8000
flagtable:  dw 5000,5000,2000,800,400,400,100       ; feet row 2..8
statetable: dw StateTitle,StatePlaying,StatePaused,StateDying
            dw StateLifeLost,StateWin,StateComplete,StateGameOver
smallpose:  dw spr_marioS,spr_marioR,spr_marioJ
superpose:  dw spr_superBS,spr_superBR,spr_superBJ

; tile tables indexed by tile code 0..12

tilefill:   db 0,C_BROWN,C_RED,C_YELLOW,C_YELLOW,C_DGRAY,C_LGREEN,C_LGREEN,C_LGREEN,C_LGREEN,C_LGRAY,0,0
tileedge:   db 0,0,0,C_BROWN,C_BROWN,0,C_GREEN,C_GREEN,C_GREEN,C_GREEN,C_DGRAY,0,0
tileextra:  dw 0,0,bricklines,qmark,qmark,0,0,0,0,0,0,coinlist,polelist
tileextcol: db 0,0,0,C_BROWN,C_BROWN,0,0,0,0,0,0,C_YELLOW,C_LGRAY

; rectangle lists: dx,dy,w,h ... 0xFF
framelist:  db 0,0,16,1, 0,15,16,1, 0,0,1,16, 15,0,1,16, 0xFF
bricklines: db 0,7,16,1, 8,0,1,7, 4,8,1,7, 12,8,1,7, 0xFF
qmark:      db 5,3,6,2, 9,5,2,3, 7,8,3,2, 7,11,2,2, 0xFF
coinlist:   db 6,1,4,14, 4,3,8,10, 0xFF
polelist:   db 7,0,2,16, 0xFF
heartlist:  db 1,0,3,2, 6,0,3,2, 0,2,10,3, 1,5,8,1, 2,6,6,1, 3,7,4,1, 0xFF

; text tables: col,row,'text',0 ... 0xFF
hudtxt:     db 1,0,'SCORE',0, 11,0,'COINS',0, 18,0,'WORLD',0, 26,0,'TIME',0
            db 33,0,'LIVES',0, 18,1,'1-1',0, 11,1,'x',0, 33,1,'x',0, 0xFF
titletxt:   db 11,4,'SUPER MARIO ENGINE',0, 15,12,'START GAME',0, 15,14,'EXIT',0
            db 16,18,'25F-0542',0
            db 16,20,'25F-0645',0, 0xFF
pausetxt:   db 17,12,'PAUSED',0, 0xFF
lltxt:      db 16,8,'WORLD 1-1',0, 20,13,'x',0, 0xFF
gotxt:      db 15,8,'GAME OVER',0, 12,11,'SCORE',0, 13,16,'PRESS ENTER',0, 0xFF
cptxt:      db 13,4,'LEVEL COMPLETE',0, 10,8,'SCORE',0, 10,10,'COINS',0
            db 10,12,'TIME LEFT',0, 25,12,'X 50',0, 13,17,'PRESS ENTER',0, 0xFF
arrow:      db '>',0

; chars -> values (converted once at start)
colchars:   db '.RrYWBGgbLkl'
colvals:    db 0,4,12,14,15,6,2,10,1,9,8,7
tilechars:  db '.#B?ME<>[]So|'
tilevals:   db 0,1,2,3,4,5,6,7,8,9,10,11,12

; enemy record 16 bytes: type(1 goomba 2 koopa),state(0 wait 1 walk 2 flat 3 shell 4 slide),
;   x,y,timer,dir(0 right 1 left), pad
enemyinit:  db 1,0 
            dw 192,144,0,1
            times 6 db 0
            db 1,0
            dw 432,144,0,1
            times 6 db 0
            db 1,0
            dw 704,144,0,1
            times 6 db 0
            db 1,0
            dw 752,144,0,1
            times 6 db 0
            db 2,0
            dw 352,144,0,1
            times 6 db 0
            db 2,0
            dw 672,144,0,1
            times 6 db 0
            times 32 db 0
enemies:    times 128 db 0
mushrec:    times 16 db 0           ; same layout, type 3

origmap:
        db '............................................................'
        db '............................................................'
        db '.........................................................|..'
        db '..............................ooo........................|..'
        db '.........................................................|..'
        db '.............................................o.o.........|..'
        db '......MBBB?..................?BBBM............?......S...|..'
        db '...................<>..ooo...........ooo............SS...|..'
        db '..............<>.o.[]..............................SSS...|..'
        db '..............[]...[].............................SSSS...S..'
        db '#######################...###########...####################'
        db '#######################...###########...####################'
workmap:    times MAPSIZE db 0

sprites:
spr_marioS:
        db '....RRRRR.......'
        db '...RRRRRRRRR....'
        db '...BBBrrBr......'
        db '..BrBrrrBrrr....'
        db '..BrBBrrrBrrr...'
        db '..BBrrrrBBBB....'
        db '....rrrrrrr.....'
        db '...RRbRRRR......'
        db '..RRRbRRbRRR....'
        db '.RRRRbbbbRRRR...'
        db '.rrRbYbbYbRrr...'
        db '.rrrbbbbbbrrr...'
        db '.rrbbbbbbbbrr...'
        db '...bbb..bbb.....'
        db '..BBB....BBB....'
        db '.BBBB....BBBB...'
spr_marioR:
        db '....RRRRR.......'
        db '...RRRRRRRRR....'
        db '...BBBrrBr......'
        db '..BrBrrrBrrr....'
        db '..BrBBrrrBrrr...'
        db '..BBrrrrBBBB....'
        db '....rrrrrrr.....'
        db '...RRbRRRR......'
        db '..RRRbRRbRRR....'
        db '.RRRRbbbbRRRR...'
        db '.rrRbYbbYbRrr...'
        db '.rrrbbbbbbrrr...'
        db '..rbbbbbbbbbr...'
        db '....bbbbbbb.....'
        db '...BBBb..BBB....'
        db '..BBB.....BBB...'
spr_marioJ:
        db '....RRRRR..rr...'
        db '...RRRRRRRRRrr..'
        db '...BBBrrBr.rrr..'
        db '..BrBrrrBrrr....'
        db '..BrBBrrrBrrr...'
        db '..BBrrrrBBBB....'
        db '....rrrrrrr.....'
        db '..rRRbRRRRR.....'
        db '.rrRRbRRbRRR....'
        db '.rrRRbbbbRRRR...'
        db '..rrbbYbbYbR....'
        db '...bbbbbbbbb....'
        db '..bbbbbbbbbbb...'
        db '.BBBbbb..bbb....'
        db '.BBB........BBB.'
        db '................'
spr_superT:
        db '....RRRRRR......'
        db '...RRRRRRRRRR...'
        db '...BBBrrBr......'
        db '..BrBrrrBrrr....'
        db '..BrBBrrrBrrr...'
        db '..BBrrrrBBBB....'
        db '....rrrrrrr.....'
        db '...RRbRRRR......'
        db '..RRRbRRbRRR....'
        db '.RRRRbbbbRRRR...'
        db '.rrRbYbbYbRrr...'
        db '.rrrbbbbbbrrr...'
        db '..rrbbbbbbbrr...'
        db '...bbbbbbbbb....'
        db '...bbbbbbbbb....'
        db '...bbbbbbbbb....'
spr_superBS:
        db '...bbbbbbbbb....'
        db '...bbbbbbbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '...bbbb.bbbb....'
        db '..BBBB...BBBB...'
        db '.BBBBB...BBBBB..'
        db '.BBBBB...BBBBB..'
        db '.BBBBB...BBBBB..'
spr_superBR:
        db '...bbbbbbbbb....'
        db '...bbbbbbbbb....'
        db '....bbbbbbbb....'
        db '....bbb.bbbb....'
        db '...bbb...bbb....'
        db '...bbb...bbb....'
        db '..bbb.....bbb...'
        db '..bbb.....bbb...'
        db '.bbb......bbb...'
        db '.bbb.......bb...'
        db '.bbb.......bb...'
        db 'BBBB.......BB...'
        db 'BBBB.......BBB..'
        db 'BBB........BBBB.'
        db 'BB..........BBB.'
        db '................'
spr_superBJ:
        db '..rbbbbbbbbbr...'
        db '..rbbbbbbbbbr...'
        db '..rrbbbbbbbrr...'
        db '...bbb...bbb....'
        db '...bbb...bbb....'
        db '...bbb...bbb....'
        db '..bbb.....bbb...'
        db '..bbb.....bbb...'
        db '..bbb.....bbb...'
        db '.bbb.......bbb..'
        db '.bbb.......bbb..'
        db '.bbb.......bbb..'
        db '.BBB.......BBB..'
        db 'BBBB.......BBBB.'
        db 'BBB.........BBB.'
        db '................'
spr_goomba:
        db '................'
        db '.....BBBBBB.....'
        db '...BBBBBBBBBB...'
        db '..BBBBBBBBBBBB..'
        db '..BBWWBBBBWWBB..'
        db '.BBBWkBBBBkWBBB.'
        db '.BBBWWBBBBWWBBB.'
        db '.BBBBBBBBBBBBBB.'
        db '..BBBBBBBBBBBB..'
        db '....rrrrrrrr....'
        db '...rrrrrrrrrr...'
        db '...rrrrrrrrrr...'
        db '....rrrrrrrr....'
        db '...kkkk..kkkk...'
        db '..kkkkk..kkkkk..'
        db '..kkkkk..kkkkk..'
spr_goombaF:
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '..BBBBBBBBBBBB..'
        db '.BBBWkBBBBkWBBB.'
        db '.BBBBBBBBBBBBBB.'
        db '..rrrrrrrrrrrr..'
        db '..kkkkkkkkkkkk..'
        db '................'
spr_koopa:
        db '......YYY.......'
        db '.....YYYYY......'
        db '.....YYWkY......'
        db '.....YYYYY......'
        db '......YYY.......'
        db '...GGGGYYY......'
        db '..GgGGGGGG......'
        db '.GgGGGgGGGG.....'
        db '.GGGGGGGGGG.....'
        db '.GgGGGGgGGG.....'
        db '.GGGGGGGGGG.....'
        db '..GGGGGGGG......'
        db '...YYYYYY.......'
        db '...YY..YY.......'
        db '..kkk..kkk......'
        db '..kkk..kkk......'
spr_shell:
        db '................'
        db '................'
        db '................'
        db '................'
        db '................'
        db '....GGGGGGGG....'
        db '..GGggGGggGGGG..'
        db '.GGggGGGGggGGGG.'
        db '.GGGGGGGGGGGGGG.'
        db '.GGggGGGGggGGGG.'
        db '.GGGGGGGGGGGGGG.'
        db '..YYYYYYYYYYYY..'
        db '...YYYYYYYYYY...'
        db '................'
        db '................'
        db '................'
spr_mush:
        db '................'
        db '................'
        db '.....RRRRRR.....'
        db '...RRRRRRRRRR...'
        db '..RRWWRRRRWWRR..'
        db '.RRRWWRRRRWWRRR.'
        db '.RRRRRRRWWRRRRR.'
        db '.RRRRRRRWWRRRRR.'
        db '..RRRRRRRRRRRR..'
        db '....WWWWWWWW....'
        db '...WWkWWWWkWW...'
        db '...WWWWWWWWWW...'
        db '...WWWWWWWWWW...'
        db '....WWWWWWWW....'
        db '................'
        db '................'
spritesend:

; ---------------- main ----------------
start:  mov ax, cs
        add ax, 0x1000              ; free 64K above our segment
        mov [bufseg], ax
        call InitData
        call InitVideo
        call HookKeyboard
        call HookTimer
        mov ax, [ticks]
        mov [lasttick], ax
        call NewGame
        mov byte [state], ST_TITLE

mainloop:
        call WaitTick
        mov bl, [state]
        cmp bl, ST_EXIT
        je quit
        xor bh, bh
        shl bx, 1
        call [statetable+bx]
        jmp mainloop

quit:   call UnhookTimer
        call UnhookKeyboard
        call RestoreText
        mov ax, 0x4c00
        int 0x21
; ------------------------------------------------------------
; InitData : convert sprite colour letters and map letters to numbers
;   in : none
;   out: sprites and origmap converted in place
;   registers changed: none
; ------------------------------------------------------------
InitData:
        push ax
        mov ax, sprites
        push ax
        mov ax, spritesend-sprites
        push ax
        mov ax, colchars
        push ax
        mov ax, colvals
        push ax
        mov ax, 12
        push ax
        call ConvertBlock
        mov ax, origmap
        push ax
        mov ax, MAPSIZE
        push ax
        mov ax, tilechars
        push ax
        mov ax, tilevals
        push ax
        mov ax, 13
        push ax
        call ConvertBlock
        pop ax
        ret

; ------------------------------------------------------------
; ConvertBlock : replace each char of a block by values[index of char in chars]
;   in : ptr, count, chars, values, n (stack)
;   out: block converted in place
;   registers changed: none
; ------------------------------------------------------------
ConvertBlock:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        push ds
        pop es
        cld
        mov si, [bp+12]
        mov dx, [bp+10]
cvnext: mov al, [si]
        mov di, [bp+8]
        mov cx, [bp+4]
        repne scasb
        jne cvzero
        mov bx, [bp+4]
        sub bx, cx
        dec bx
        add bx, [bp+6]
        mov al, [bx]
        mov [si], al
        jmp cvstep
cvzero: mov byte [si], 0
cvstep: inc si
        dec dx
        jnz cvnext
        pop es
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret 10

; ================= MODULE 2: video =================
; InitVideo : switch to VGA mode 13h (INT 10h)
;   in : none
;   out: none
;   registers changed: none
; ------------------------------------------------------------
InitVideo:
        push ax
        mov ax, 0x0013              ; mode 13h
        int 0x10
        pop ax
        ret

; ------------------------------------------------------------
; RestoreText : back to text mode 3 (INT 10h)
;   in : none
;   out: none
;   registers changed: none
; ------------------------------------------------------------
RestoreText:
        push ax
        mov ax, 0x0003
        int 0x10
        pop ax
        ret

; ------------------------------------------------------------
; PutPixel : plot one pixel in the frame buffer, clipped
;   in : x, y, colour (stack)
;   out: pixel in buffer
;   registers changed: none
; ------------------------------------------------------------
PutPixel:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push di
        push es
        mov ax, [bp+8]
        mov bx, [bp+6]
        cmp ax, 0
        jl ppend
        cmp ax, SCRW
        jge ppend
        cmp bx, 0
        jl ppend
        cmp bx, 200
        jge ppend
        mov di, bx
        shl di, 1
        shl di, 1
        add di, bx                  ; y*5
        mov cl, 6
        shl di, cl                  ; y*320
        add di, ax
        mov ax, [bufseg]
        mov es, ax
        mov al, [bp+4]
        mov [es:di], al
ppend:  pop es
        pop di
        pop cx
        pop bx
        pop ax
        pop bp
        ret 6

; ------------------------------------------------------------
; FillRect : fill a rectangle in the frame buffer, clipped on all sides
;   in : x, y, w, h, colour (stack)
;   out: rectangle in buffer
;   registers changed: none
; ------------------------------------------------------------
FillRect:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        mov ax, [bufseg]
        mov es, ax
        mov si, [bp+12]
        mov di, [bp+10]
        mov bx, [bp+8]
        mov dx, [bp+6]
        cmp si, 0
        jge fr1
        add bx, si
        xor si, si
fr1:    mov ax, SCRW
        sub ax, si
        cmp bx, ax
        jle fr2
        mov bx, ax
fr2:    cmp bx, 0
        jle frend
        cmp di, 0
        jge fr3
        add dx, di
        xor di, di
fr3:    mov ax, 200
        sub ax, di
        cmp dx, ax
        jle fr4
        mov dx, ax
fr4:    cmp dx, 0
        jle frend
        mov ax, di
        shl ax, 1
        shl ax, 1
        add ax, di
        mov cl, 6
        shl ax, cl                  ; y*320
        add ax, si
        mov di, ax
        mov al, [bp+4]
        cld
frrow:  mov cx, bx
        push di
        rep stosb
        pop di
        add di, SCRW
        dec dx
        jnz frrow
frend:  pop es
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret 10

; ------------------------------------------------------------
; DrawRects : draw a list of rectangles (dx,dy,w,h ... 0xFF) relative to x,y
;   in : x, y, list address, colour (stack)
;   out: rectangles in buffer
;   registers changed: none
; ------------------------------------------------------------
DrawRects:
        push bp
        mov bp, sp
        push ax
        push si
        mov si, [bp+6]
drl:    cmp byte [si], 0xFF
        je drend
        mov al, [si]
        xor ah, ah
        add ax, [bp+10]
        push ax
        mov al, [si+1]
        xor ah, ah
        add ax, [bp+8]
        push ax
        mov al, [si+2]
        xor ah, ah
        push ax
        mov al, [si+3]
        xor ah, ah
        push ax
        push word [bp+4]
        call FillRect
        add si, 4
        jmp drl
drend:  pop si
        pop ax
        pop bp
        ret 8

; ================= MODULE 3: map =================
; ------------------------------------------------------------
; TileIndex : map offset of the tile under a pixel
;   in : px, py (stack)
;   out: AX = row*60+col, -1 outside left/right, -2 outside top/bottom
;   registers changed: AX
; ------------------------------------------------------------
TileIndex:
        push bp
        mov bp, sp
        push bx
        push cx
        push dx
        mov ax, [bp+6]
        mov bx, [bp+4]
        cmp ax, 0
        jl tihout
        cmp ax, LEVELPX
        jge tihout
        cmp bx, 0
        jl tivout
        cmp bx, MAPPX
        jge tivout
        mov cl, TILESHIFT
        shr ax, cl                  ; column
        shr bx, cl                  ; row
        mov cx, ax
        mov ax, MAPW
        mul bx
        add ax, cx
        jmp tiend
tihout: mov ax, -1
        jmp tiend
tivout: mov ax, -2
tiend:  pop dx
        pop cx
        pop bx
        pop bp
        ret 4

; ------------------------------------------------------------
; GetTile : tile code under a pixel of the working map
;   in : px, py (stack)
;   out: AX = tile code (sides = ground, top/bottom = sky)
;   registers changed: AX
; ------------------------------------------------------------
GetTile:
        push bp
        mov bp, sp
        push bx
        push word [bp+6]
        push word [bp+4]
        call TileIndex
        cmp ax, -1
        je gtsolid
        cmp ax, -2
        je gtsky
        mov bx, ax
        mov al, [workmap+bx]
        xor ah, ah
        jmp gtend
gtsolid: mov ax, 1
        jmp gtend
gtsky:  xor ax, ax
gtend:  pop bx
        pop bp
        ret 4

; ------------------------------------------------------------
; Solid : is the tile under a pixel solid (codes 1..10)
;   in : px, py (stack)
;   out: AX = 1 solid, 0 not
;   registers changed: AX
; ------------------------------------------------------------
Solid:
        push bp
        mov bp, sp
        push word [bp+6]
        push word [bp+4]
        call GetTile
        cmp ax, T_GROUND
        jb sono
        cmp ax, T_LASTSOLID
        ja sono
        mov ax, 1
        jmp soend
sono:   xor ax, ax
soend:  pop bp
        ret 4

; ------------------------------------------------------------
; DrawTile : draw one 16x16 tile
;   in : x, y, tile code (stack)
;   out: tile in buffer
;   registers changed: none
; ------------------------------------------------------------
DrawTile:
        push bp
        mov bp, sp
        push ax
        push bx
        push si
        mov bx, [bp+4]
        mov al, [tilefill+bx]
        or al, al
        jz dtex
        push word [bp+8]
        push word [bp+6]
        mov ax, TILE
        push ax
        push ax
        mov al, [tilefill+bx]
        xor ah, ah
        push ax
        call FillRect
        push word [bp+8]
        push word [bp+6]
        mov ax, framelist
        push ax
        mov al, [tileedge+bx]
        xor ah, ah
        push ax
        call DrawRects
dtex:   mov si, bx
        shl si, 1
        mov ax, [tileextra+si]
        or ax, ax
        jz dtend
        push word [bp+8]
        push word [bp+6]
        push ax
        mov al, [tileextcol+bx]
        xor ah, ah
        push ax
        call DrawRects
dtend:  pop si
        pop bx
        pop ax
        pop bp
        ret 6

; ------------------------------------------------------------
; DrawMap : draw the 21 visible tile columns, scrolled by camerax
;   in : none (camerax)
;   out: tiles in buffer
;   registers changed: none
; ------------------------------------------------------------
DrawMap:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov bx, [camerax]
        mov cl, TILESHIFT
        shr bx, cl
        shl bx, cl                  ; world x of first column
        mov dx, [camerax]
        and dx, 15
        neg dx                      ; screen x of first column
        xor si, si
dmcol:  cmp bx, LEVELPX
        jge dmend
        xor di, di
dmrow:  push bx
        push di
        call GetTile
        or ax, ax
        jz dmskip
        push dx
        push di
        push ax
        call DrawTile
dmskip: add di, TILE
        cmp di, MAPPX
        jne dmrow
        add bx, TILE
        add dx, TILE
        inc si
        cmp si, VISCOLS
        jne dmcol
dmend:  pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ------------------------------------------------------------
; ResetMap : copy original map to working map (rep movsb)
;   in : none
;   out: workmap restored
;   registers changed: none
; ------------------------------------------------------------
ResetMap:
        push cx
        push si
        push di
        push es
        push ds
        pop es
        mov si, origmap
        mov di, workmap
        mov cx, MAPSIZE
        cld
        rep movsb
        pop es
        pop di
        pop si
        pop cx
        ret

; ================= MODULE 4: sprites =================
; ------------------------------------------------------------
; DrawSprite : draw a 16x16 sprite, colour 0 transparent, clipped, optional mirror
;   in : x, y, sprite address, flags bit0=mirror (stack)
;   out: sprite in buffer
;   registers changed: none
; ------------------------------------------------------------
DrawSprite:
        push bp
        mov bp, sp
        sub sp, 4
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        mov ax, [bufseg]
        mov es, ax
        mov si, [bp+6]
        mov ax, si
        add ax, 256
        mov [bp-2], ax              ; end of sprite data
        mov ax, [bp+8]
        mov [bp-4], ax              ; current y
dsrow:  mov ax, [bp-4]
        cmp ax, 0
        jl dsnext
        cmp ax, 200
        jge dsnext
        mov di, ax
        shl di, 1
        shl di, 1
        add di, ax
        mov cl, 6
        shl di, cl                  ; y*320
        xor dx, dx
dscol:  mov bx, [bp+10]
        add bx, dx
        cmp bx, 0
        jl dsskip
        cmp bx, SCRW
        jge dsskip
        mov cx, dx
        test byte [bp+4], 1
        jz dsnm
        mov cx, 15
        sub cx, dx
dsnm:   add si, cx
        mov al, [si]
        sub si, cx
        or al, al
        jz dsskip
        mov [es:bx+di], al
dsskip: inc dx
        cmp dx, 16
        jne dscol
dsnext: add si, 16
        inc word [bp-4]
        cmp si, [bp-2]
        jne dsrow
        pop es
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        mov sp, bp
        pop bp
        ret 8

; ================= MODULE 5: frame buffer =================
; ------------------------------------------------------------
; ClearBuffer : fill the whole frame buffer with a colour (rep stosw)
;   in : colour (stack)
;   out: buffer cleared
;   registers changed: none
; ------------------------------------------------------------
ClearBuffer:                        ; colour
        push bp
        mov bp, sp
        push ax
        push cx
        push di
        push es
        mov ax, [bufseg]
        mov es, ax
        mov ax, [bp+4]
        mov ah, al
        xor di, di
        mov cx, 32000
        cld
        rep stosw
        pop es
        pop di
        pop cx
        pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; FlipBuffer : copy frame buffer to video memory (rep movsw)
;   in : none
;   out: screen updated
;   registers changed: none
; ------------------------------------------------------------
FlipBuffer:
        push ax
        push cx
        push si
        push di
        push ds
        push es
        mov ax, [bufseg]
        mov ds, ax
        mov ax, 0xA000
        mov es, ax
        xor si, si
        xor di, di
        mov cx, 32000
        cld
        rep movsw
        pop es
        pop ds
        pop di
        pop si
        pop cx
        pop ax
        ret

; ================= MODULE 6: camera =================
; ------------------------------------------------------------
; UpdateCamera : scroll right only after screen x 160, clamp 0..640, left wall
;   in : none (mx, camerax)
;   out: camerax, mx, mvx
;   registers changed: none
; ------------------------------------------------------------
UpdateCamera:
        push ax
        mov ax, [mx]
        sub ax, [camerax]
        cmp ax, CAMFOLLOW
        jle ucwall
        mov ax, [mx]
        sub ax, CAMFOLLOW
        cmp ax, MAXCAM
        jle uc1
        mov ax, MAXCAM
uc1:    cmp ax, [camerax]           ; never scroll back
        jle ucwall
        mov [camerax], ax
ucwall: mov ax, [camerax]
        cmp [mx], ax                ; left wall
        jge ucend
        mov [mx], ax
        mov byte [mxf], 0
        cmp word [mvx], 0
        jge ucend
        mov word [mvx], 0
ucend:  pop ax
        ret

; ================= MODULE 7: keyboard =================
; ------------------------------------------------------------
; kbisr : INT 9 handler: key table, one-shot kbpress, EOI
;   in : port 60h
;   out: keys[], kbpress
;   registers changed: none (saved)
; ------------------------------------------------------------
kbisr:  push ax
        push bx
        in al, 0x60
        cmp al, 0xE0                ; extended prefix: ignore
        je kbdone
        mov bl, al
        and bl, 0x7F
        xor bh, bh
        test al, 0x80
        jnz kbrel
        cmp byte [cs:keys+bx], 0    ; typematic repeat?
        jne kbdone
        mov byte [cs:keys+bx], 1
        mov [cs:kbpress], bl
        jmp kbdone
kbrel:  mov byte [cs:keys+bx], 0
kbdone: mov al, 0x20
        out 0x20, al                ; EOI
        pop bx
        pop ax
        iret

; ------------------------------------------------------------
; HookKeyboard : save old INT 9 vector and install kbisr
;   in : none
;   out: oldkb
;   registers changed: none
; ------------------------------------------------------------
HookKeyboard:
        push ax
        push es
        xor ax, ax
        mov es, ax
        mov ax, [es:9*4]
        mov [oldkb], ax
        mov ax, [es:9*4+2]
        mov [oldkb+2], ax
        cli
        mov word [es:9*4], kbisr
        mov [es:9*4+2], cs
        sti
        pop es
        pop ax
        ret

; ------------------------------------------------------------
; UnhookKeyboard : restore the old INT 9 vector
;   in : none
;   out: none
;   registers changed: none
; ------------------------------------------------------------
UnhookKeyboard:
        push ax
        push es
        xor ax, ax
        mov es, ax
        cli
        mov ax, [oldkb]
        mov [es:9*4], ax
        mov ax, [oldkb+2]
        mov [es:9*4+2], ax
        sti
        pop es
        pop ax
        ret

; ================= MODULE 8: timer =================
; ------------------------------------------------------------
; timerisr : INT 8 handler: count ticks, pass 3 of 5 ticks to BIOS
;   in : none
;   out: ticks
;   registers changed: none (saved)
; ------------------------------------------------------------
timerisr:
        inc word [cs:ticks]
        add byte [cs:acc], 3        ; 3 of every 5 ticks go to BIOS (30 Hz -> 18.2 Hz)
        cmp byte [cs:acc], 5
        jb tnoch
        sub byte [cs:acc], 5
        jmp far [cs:oldtimer]
tnoch:  push ax
        mov al, 0x20
        out 0x20, al
        pop ax
        iret

; ------------------------------------------------------------
; HookTimer : save INT 8, install timerisr, program PIT to 30 Hz
;   in : none
;   out: oldtimer
;   registers changed: none
; ------------------------------------------------------------
HookTimer:
        push ax
        push es
        xor ax, ax
        mov es, ax
        mov ax, [es:8*4]
        mov [oldtimer], ax
        mov ax, [es:8*4+2]
        mov [oldtimer+2], ax
        cli
        mov word [es:8*4], timerisr
        mov [es:8*4+2], cs
        mov al, 0x36
        out 0x43, al
        mov al, PITLO
        out 0x40, al
        mov al, PITHI               ; divisor 39773 = 30 Hz
        out 0x40, al
        sti
        pop es
        pop ax
        ret

; ------------------------------------------------------------
; UnhookTimer : restore PIT divisor and INT 8 vector
;   in : none
;   out: none
;   registers changed: none
; ------------------------------------------------------------
UnhookTimer:
        push ax
        push es
        xor ax, ax
        mov es, ax
        cli
        mov al, 0x36
        out 0x43, al
        xor al, al
        out 0x40, al
        out 0x40, al                ; divisor 0 = 65536 (18.2 Hz)
        mov ax, [oldtimer]
        mov [es:8*4], ax
        mov ax, [oldtimer+2]
        mov [es:8*4+2], ax
        sti
        pop es
        pop ax
        ret

; ------------------------------------------------------------
; WaitTick : wait until the tick counter changes
;   in : none
;   out: delta = ticks passed
;   registers changed: none
; ------------------------------------------------------------
WaitTick:
        push ax
        push dx
wt:     mov dx, [ticks]
        mov ax, dx
        sub ax, [lasttick]
        jz wt
        cmp ax, 4
        jbe wt1
        mov ax, 4
wt1:    mov [delta], ax
        mov [lasttick], dx
        pop dx
        pop ax
        ret

; ------------------------------------------------------------
; UpdateClock : count seconds from ticks; at 0 Mario dies
;   in : none (delta)
;   out: timeleft
;   registers changed: none
; ------------------------------------------------------------
UpdateClock:
        push ax
        mov ax, [delta]
        add [tickcount], ax
ucl1:   cmp word [tickcount], TICKSEC
        jb uclend
        sub word [tickcount], TICKSEC
        dec word [timeleft]
        jnz ucl1
        call KillMario
        mov word [tickcount], 0
uclend: pop ax
        ret

; ================= MODULE 9: movement / physics (8.8 fixed point) =================
; ------------------------------------------------------------
; UpdateMario : keys, acceleration, friction, jump, gravity, then move
;   in : none (keys[])
;   out: hero variables
;   registers changed: none
; ------------------------------------------------------------
UpdateMario:
        push ax
        push bx
        mov bx, WALKMAX              ; walk limit
        cmp byte [keys+SC_LSHIFT], 0
        je um1
        mov bx, RUNMAX              ; run limit
um1:    mov al, [keys+SC_RIGHT]
        mov ah, [keys+SC_LEFT]
        cmp al, ah
        je umfric
        or al, al
        jz umleft
        mov byte [facing], 0        ; right
        mov ax, WALKACC
        cmp word [mvx], 0
        jge um2
        mov ax, BRAKEACC                ; braking
um2:    add [mvx], ax
        cmp [mvx], bx
        jle umjump
        mov [mvx], bx
        jmp umjump
umleft: mov byte [facing], 1
        mov ax, WALKACC
        cmp word [mvx], 0
        jle um3
        mov ax, BRAKEACC
um3:    sub [mvx], ax
        neg bx
        cmp [mvx], bx
        jge umjump
        mov [mvx], bx
        jmp umjump
umfric: mov ax, [mvx]
        cmp ax, 0
        jg umfpos
        jl umfneg
        jmp umjump
umfpos: sub ax, FRICTION
        jge umfst
        xor ax, ax
        jmp umfst
umfneg: add ax, FRICTION
        jle umfst
        xor ax, ax
umfst:  mov [mvx], ax
umjump: cmp byte [keys+SC_SPACE], 0
        je umnosp
        cmp byte [onground], 0
        je umgrav
        cmp byte [jumplock], 0
        jne umgrav
        mov word [mvy], JUMPV      ; jump start speed
        mov byte [onground], 0
        mov byte [jumplock], 1
        jmp umgrav
umnosp: mov byte [jumplock], 0
        cmp word [mvy], JUMPCUT      ; variable jump height cut-off
        jge umgrav
        mov word [mvy], JUMPCUT
umgrav: add word [mvy], GRAVITY
        cmp word [mvy], MAXFALL
        jle umgo
        mov word [mvy], MAXFALL
umgo:   call MoveMarioX
        call MoveMarioY
        cmp word [invuln], 0
        je um4
        dec word [invuln]
um4:    cmp word [my], MAPPX          ; fell into a pit
        jl umend
        call KillMario
umend:  pop bx
        pop ax
        ret

; ================= MODULE 10: collision =================
; ------------------------------------------------------------
; CheckSide : is the hitbox column at x blocked by a solid tile
;   in : x (stack)
;   out: AX = 1 blocked
;   registers changed: AX
; ------------------------------------------------------------
CheckSide:
        push bp
        mov bp, sp
        push bx
        push cx
        mov bx, [my]
        mov cx, [my]
        add cx, [mh]
        dec cx                      ; last pixel row of hitbox
csl:    push word [bp+4]
        push bx
        call Solid
        or ax, ax
        jnz csout
        cmp bx, cx
        jge csout
        add bx, 15
        cmp bx, cx
        jle csl
        mov bx, cx
        jmp csl
csout:  pop cx
        pop bx
        pop bp
        ret 2

; ------------------------------------------------------------
; CheckHoriz : is the hitbox row at y blocked by a solid tile
;   in : y (stack)
;   out: AX = 1 blocked
;   registers changed: AX
; ------------------------------------------------------------
CheckHoriz:
        push bp
        mov bp, sp
        mov ax, [mx]
        add ax, 2
        push ax
        push word [bp+4]
        call Solid
        or ax, ax
        jnz chout
        mov ax, [mx]
        add ax, 13
        push ax
        push word [bp+4]
        call Solid
chout:  pop bp
        ret 2

; ------------------------------------------------------------
; MoveMarioX : apply mvx, stop at walls
;   in : none
;   out: mx, mxf, mvx
;   registers changed: none
; ------------------------------------------------------------
MoveMarioX:
        push ax
        mov ax, [mvx]
        add [mxf], al
        mov al, ah
        cbw
        adc [mx], ax
        cmp word [mvx], 0
        je mxend
        jl mxleft
        mov ax, [mx]
        add ax, 13
        push ax
        call CheckSide
        or ax, ax
        jz mxend
        mov ax, [mx]
        add ax, 13
        and ax, 0xFFF0
        sub ax, 14
        mov [mx], ax
        jmp mxstop
mxleft: mov ax, [mx]
        add ax, 2
        push ax
        call CheckSide
        or ax, ax
        jz mxend
        mov ax, [mx]
        add ax, 2
        and ax, 0xFFF0
        add ax, 14
        mov [mx], ax
mxstop: mov byte [mxf], 0
        mov word [mvx], 0
mxend:  pop ax
        ret

; ------------------------------------------------------------
; MoveMarioY : apply mvy, land on floors, hit blocks with the head
;   in : none
;   out: my, myf, mvy, onground
;   registers changed: none
; ------------------------------------------------------------
MoveMarioY:
        push ax
        push bx
        push cx
        mov ax, [mvy]
        add [myf], al
        mov al, ah
        cbw
        adc [my], ax
        cmp word [mvy], 0
        jl myhead
        mov ax, [my]
        add ax, [mh]
        dec ax
        mov bx, ax                  ; feet pixel row
        push ax
        call CheckHoriz
        or ax, ax
        jz myprobe
        and bx, 0xFFF0
        sub bx, [mh]
        mov [my], bx                ; stand on the tile
        mov byte [myf], 0
        mov word [mvy], 0
myprobe: mov ax, [my]
        add ax, [mh]
        push ax
        call CheckHoriz
        mov [onground], al
        or al, al
        jz myend
        mov byte [chain], 0
        jmp myend
myhead: mov byte [onground], 0
        push word [my]
        call CheckHoriz
        or ax, ax
        jz myend
        mov cl, TILESHIFT
        mov ax, [mx]
        add ax, 8
        shr ax, cl                  ; column under head centre
        mov bx, [my]
        shr bx, cl                  ; row
        push ax
        push bx
        call HitBlock
        mov ax, [my]
        and ax, 0xFFF0
        add ax, 16
        mov [my], ax
        mov byte [myf], 0
        mov word [mvy], 0
myend:  pop cx
        pop bx
        pop ax
        ret

; ------------------------------------------------------------
; RectOverlap : rectangle overlap test
;   in : x1,y1,w1,h1,x2,y2,w2,h2 (stack)
;   out: AX = 1 overlap
;   registers changed: AX
; ------------------------------------------------------------
RectOverlap:
        push bp
        mov bp, sp
        push bx
        mov ax, [bp+18]
        mov bx, [bp+10]
        add bx, [bp+6]
        cmp ax, bx
        jge rono
        mov ax, [bp+10]
        mov bx, [bp+18]
        add bx, [bp+14]
        cmp ax, bx
        jge rono
        mov ax, [bp+16]
        mov bx, [bp+8]
        add bx, [bp+4]
        cmp ax, bx
        jge rono
        mov ax, [bp+8]
        mov bx, [bp+16]
        add bx, [bp+12]
        cmp ax, bx
        jge rono
        mov ax, 1
        jmp roend
rono:   xor ax, ax
roend:  pop bx
        pop bp
        ret 16

; ================= MODULE 11: enemies =================
; ------------------------------------------------------------
; EntWalk : move an entity in its direction, turn at walls (and ledges)
;   in : entity ptr, dx, edge flag (stack)
;   out: entity x, dir
;   registers changed: none
; ------------------------------------------------------------
EntWalk:
        push bp
        mov bp, sp
        sub sp, 4
        push ax
        push bx
        push si
        mov si, [bp+8]
        mov ax, [bp+6]
        cmp word [si+8], 0
        je ewr
        neg ax
ewr:    add ax, [si+2]
        mov [bp-2], ax              ; new x
        mov bx, ax
        cmp word [si+8], 0
        jne ewl
        add bx, 15
ewl:    mov [bp-4], bx              ; leading edge x
        push bx
        mov ax, [si+4]
        add ax, 2
        push ax
        call Solid
        or ax, ax
        jnz ewturn
        push word [bp-4]
        mov ax, [si+4]
        add ax, 15
        push ax
        call Solid
        or ax, ax
        jnz ewturn
        cmp word [bp+4], 0
        je ewgo
        push word [bp-4]
        mov ax, [si+4]
        add ax, 16
        push ax
        call Solid
        or ax, ax
        jnz ewgo
ewturn: xor word [si+8], 1
        jmp ewend
ewgo:   mov ax, [bp-2]
        mov [si+2], ax
ewend:  pop si
        pop bx
        pop ax
        mov sp, bp
        pop bp
        ret 6

; ------------------------------------------------------------
; EntFall : gravity and landing for an entity
;   in : entity ptr (stack)
;   out: entity y
;   registers changed: none
; ------------------------------------------------------------
EntFall:
        push bp
        mov bp, sp
        push ax
        push bx
        push si
        mov si, [bp+4]
        mov bx, [si+4]
        add bx, 16
        mov ax, [si+2]
        add ax, 4
        push ax
        push bx
        call Solid
        or ax, ax
        jnz efland
        mov ax, [si+2]
        add ax, 11
        push ax
        push bx
        call Solid
        or ax, ax
        jnz efland
        add word [si+4], 2
        jmp efend
efland: and bx, 0xFFF0
        sub bx, 16
        mov [si+4], bx
efend:  pop si
        pop bx
        pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; HitOther : find another live enemy overlapping this one
;   in : entity ptr (stack)
;   out: AX = other ptr or 0
;   registers changed: AX
; ------------------------------------------------------------
HitOther:
        push bp
        mov bp, sp
        push si
        push di
        mov si, [bp+4]
        mov di, enemies
hol:    cmp di, si
        je hon
        cmp byte [di], 0
        je hon
        cmp byte [di+1], 0
        je hon
        cmp byte [di+1], 2
        je hon
        mov ax, [si+2]
        add ax, 2
        push ax
        push word [si+4]
        mov ax, 12
        push ax
        mov ax, 16
        push ax
        mov ax, [di+2]
        add ax, 2
        push ax
        push word [di+4]
        mov ax, 12
        push ax
        mov ax, 16
        push ax
        call RectOverlap
        or ax, ax
        jz hon
        mov ax, di
        jmp hoend
hon:    add di, 16
        cmp di, enemies+128
        jne hol
        xor ax, ax
hoend:  pop di
        pop si
        pop bp
        ret 2

; ------------------------------------------------------------
; UpdateEnemy : one frame of Goomba / Koopa / shell behaviour
;   in : enemy ptr (stack)
;   out: enemy record, score
;   registers changed: none
; ------------------------------------------------------------
UpdateEnemy:
        push bp
        mov bp, sp
        push ax
        push bx
        push si
        mov si, [bp+4]
        cmp byte [si], 0
        jne jf1
        jmp ueend
jf1:
        mov ax, [camerax]
        sub ax, 32
        cmp [si+2], ax
        jge jf2
        jmp uekill
jf2:
        cmp word [si+4], MAPPX
        jl jf3
        jmp uekill
jf3:
        mov al, [si+1]
        cmp al, 0
        jne ue1
        mov ax, [camerax]           ; waiting: wake up near the screen
        add ax, 336
        cmp [si+2], ax
        jl jf4
        jmp ueend
jf4:
        mov byte [si+1], 1
        mov word [si+8], 1
        jmp ueend
ue1:    cmp al, 2                   ; flat goomba
        jne ue2
        dec word [si+6]
        jz jf5
        jmp ueend
jf5:
        jmp uekill
ue2:    cmp word [si+6], 0
        je ue3
        dec word [si+6]
ue3:    push si
        call EntFall
        mov al, [si+1]
        cmp al, 3
        jne jf6
        jmp ueend
jf6:
        cmp al, 4
        je ueslide
        xor bx, bx
        cmp byte [si], 2
        je uek
        test byte [frame], 1        ; goomba 0.5 px/frame
        jz jf7
        jmp ueend
jf7:
        jmp uewalk
uek:    test byte [frame], 3        ; koopa 0.75 px/frame, turns at ledges
        jnz jf8
        jmp ueend
jf8:
        mov bx, 1
uewalk: push si
        mov ax, 1
        push ax
        push bx
        call EntWalk
        push si
        call HitOther
        or ax, ax
        jnz jf9
        jmp ueend
jf9:
        xor word [si+8], 1
        jmp ueend
ueslide: push si
        mov ax, 3
        push ax
        xor ax, ax
        push ax
        call EntWalk
        push si
        call HitOther
        or ax, ax
        jnz jf10
        jmp ueend
jf10:
        mov bx, ax
        mov byte [bx], 0
        mov ax, 500
        push ax
        call AddScore
        jmp ueend
uekill: mov byte [si], 0
ueend:  pop si
        pop bx
        pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; UpdateEnemies : update every enemy record
;   in : none
;   out: enemy table
;   registers changed: none
; ------------------------------------------------------------
UpdateEnemies:
        push si
        mov si, enemies
ues:    push si
        call UpdateEnemy
        add si, 16
        cmp si, enemies+128
        jne ues
        pop si
        ret

; ------------------------------------------------------------
; DrawEnemies : draw enemies and the mushroom
;   in : none
;   out: sprites in buffer
;   registers changed: none
; ------------------------------------------------------------
DrawEnemies:
        push ax
        push cx
        push dx
        push si
        push di
        mov si, enemies
dene:   cmp byte [si], 0
        je denext
        mov ax, [si+2]
        sub ax, [camerax]
        cmp ax, -16
        jle denext
        cmp ax, SCRW
        jge denext
        xor dx, dx
        cmp byte [si], 2
        je dekoopa
        mov di, spr_goomba
        cmp byte [si+1], 2
        jne dewalk
        mov di, spr_goombaF
        jmp dego
dewalk: mov dl, [frame]
        mov cl, 3
        shr dl, cl
        and dl, 1
        jmp dego
dekoopa: mov di, spr_koopa
        mov dx, [si+8]
        cmp byte [si+1], 3
        jb dego
        mov di, spr_shell
        xor dx, dx
dego:   push ax
        push word [si+4]
        push di
        push dx
        call DrawSprite
denext: add si, 16
        cmp si, enemies+128
        jne dene
        cmp byte [mushrec], 0
        je deend
        mov ax, [mushrec+2]
        sub ax, [camerax]
        push ax
        push word [mushrec+4]
        mov ax, spr_mush
        push ax
        xor ax, ax
        push ax
        call DrawSprite
deend:  pop di
        pop si
        pop dx
        pop cx
        pop ax
        ret

; ------------------------------------------------------------
; CheckEnemies : Mario against every enemy
;   in : none
;   out: see CheckEntity
;   registers changed: none
; ------------------------------------------------------------
CheckEnemies:
        push si
        mov si, enemies
cel:    push si
        call CheckEntity
        add si, 16
        cmp si, enemies+128
        jne cel
        pop si
        ret

; ------------------------------------------------------------
; CheckEntity : stomp, hurt or kick decision for one enemy
;   in : enemy ptr (stack)
;   out: score, Mario, enemy
;   registers changed: none
; ------------------------------------------------------------
CheckEntity:
        push bp
        mov bp, sp
        push ax
        push bx
        push si
        mov si, [bp+4]
        cmp byte [si], 0
        jne jf11
        jmp ceend
jf11:
        mov al, [si+1]
        cmp al, 0
        jne jf12
        jmp ceend
jf12:
        cmp al, 2
        jne jf13
        jmp ceend
jf13:
        cmp al, 3
        jb ce1
        cmp word [si+6], 0          ; shell grace frames
        je jf14
        jmp ceend
jf14:
ce1:    mov ax, [mx]
        add ax, 2
        push ax
        push word [my]
        mov ax, 12
        push ax
        push word [mh]
        push word [si+2]
        push word [si+4]
        mov ax, 16
        push ax
        push ax
        call RectOverlap
        or ax, ax
        jnz jf15
        jmp ceend
jf15:
        cmp byte [si+1], 3
        je cekick
        cmp word [mvy], 0
        jle ceside
        mov ax, [my]
        add ax, [mh]
        mov bx, [si+4]
        add bx, 12
        cmp ax, bx                  ; feet still in upper part of enemy = stomp
        jg ceside
        cmp byte [si+1], 4
        jne ce2
        mov byte [si+1], 3          ; sliding shell stops
        mov word [si+6], GRACEFRAMES
        jmp cescore
ce2:    cmp byte [si], 2
        je ce3
        mov byte [si+1], 2          ; goomba flat
        mov word [si+6], FLATFRAMES
        jmp cescore
ce3:    mov byte [si+1], 3          ; koopa to shell
        mov word [si+6], GRACEFRAMES
cescore: call ChainScore
        mov ax, [si+4]
        sub ax, [mh]
        mov [my], ax
        mov byte [myf], 0
        mov word [mvy], BOUNCE      ; bounce
        cmp byte [keys+SC_SPACE], 0
        jne jf16
        jmp ceend
jf16:
        mov word [mvy], BOUNCEHI
        jmp ceend
ceside: call HurtMario
        jmp ceend
cekick: mov byte [si+1], 4
        mov word [si+6], GRACEFRAMES
        mov word [si+8], 0
        mov ax, [mx]
        add ax, 8
        mov bx, [si+2]
        add bx, 8
        cmp ax, bx
        jl cek2
        mov word [si+8], 1
cek2:   mov ax, 400
        push ax
        call AddScore
ceend:  pop si
        pop bx
        pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; ChainScore : points for the next stomp of the chain table, 1-UP after 10
;   in : none (chain)
;   out: score or lives
;   registers changed: none
; ------------------------------------------------------------
ChainScore:
        push ax
        push bx
        mov al, [chain]
        cmp al, 10
        jae csup
        xor ah, ah
        mov bx, ax
        shl bx, 1
        mov ax, [chaintable+bx]
        push ax
        call AddScore
        jmp cs1
csup:   call AddLife
cs1:    cmp byte [chain], 255
        je cs2
        inc byte [chain]
cs2:    pop bx
        pop ax
        ret

; ================= MODULE 12: blocks, coins, power-ups =================
; ------------------------------------------------------------
; HitBlock : brick / ? block hit from below
;   in : column, row (stack)
;   out: working map, score, mushroom
;   registers changed: none
; ------------------------------------------------------------
HitBlock:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push dx
        mov ax, [bp+4]
        mov bx, MAPW
        mul bx
        add ax, [bp+6]
        mov bx, ax
        mov al, [workmap+bx]
        cmp al, T_BRICK
        je hbbrick
        cmp al, T_QCOIN
        je hbcoin
        cmp al, T_QMUSH
        je hbmush
        jmp hbend
hbbrick: cmp byte [form], 1
        jne hbend
        mov byte [workmap+bx], T_SKY
        mov ax, 50
        push ax
        call AddScore
        jmp hbend
hbcoin: mov byte [workmap+bx], T_EMPTY
        mov ax, 200
        push ax
        call AddScore
        call AddCoin
        jmp hbend
hbmush: mov byte [workmap+bx], T_EMPTY
        mov cl, TILESHIFT
        mov byte [mushrec], 3
        mov byte [mushrec+1], 1
        mov ax, [bp+6]
        shl ax, cl
        mov [mushrec+2], ax
        mov ax, [bp+4]
        dec ax
        shl ax, cl
        mov [mushrec+4], ax
        mov word [mushrec+6], 0
        mov word [mushrec+8], 0
hbend:  pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret 4

; ------------------------------------------------------------
; UpdateMushroom : move the mushroom and test Mario touching it
;   in : none
;   out: mushroom record
;   registers changed: none
; ------------------------------------------------------------
UpdateMushroom:
        push ax
        cmp byte [mushrec], 0
        je umsend
        mov ax, mushrec
        push ax
        call EntFall
        mov ax, mushrec
        push ax
        mov ax, 1
        push ax
        xor ax, ax
        push ax
        call EntWalk
        cmp word [mushrec+4], MAPPX
        jge umskill
        mov ax, [camerax]
        sub ax, 32
        cmp [mushrec+2], ax
        jl umskill
        mov ax, [mx]
        add ax, 2
        push ax
        push word [my]
        mov ax, 12
        push ax
        push word [mh]
        push word [mushrec+2]
        push word [mushrec+4]
        mov ax, 16
        push ax
        push ax
        call RectOverlap
        or ax, ax
        jz umsend
        mov byte [mushrec], 0
        call MakeSuper
        jmp umsend
umskill: mov byte [mushrec], 0
umsend: pop ax
        ret

; ------------------------------------------------------------
; MakeSuper : +1000, small Mario becomes Super with feet fixed
;   in : none
;   out: form, hp, mh, my
;   registers changed: none
; ------------------------------------------------------------
MakeSuper:
        push ax
        mov ax, 1000
        push ax
        call AddScore
        cmp byte [form], 1
        je mssend
        mov byte [form], 1
        mov byte [hp], 2
        mov word [mh], 32
        sub word [my], 16
mssend: pop ax
        ret

; ------------------------------------------------------------
; HurtMario : super becomes small with blink, small dies
;   in : none
;   out: form, hp, invuln
;   registers changed: none
; ------------------------------------------------------------
HurtMario:
        cmp word [invuln], 0
        jne hmend
        cmp byte [form], 1
        jne hmdie
        mov byte [form], 0
        mov byte [hp], 1
        mov word [mh], 16
        add word [my], 16
        mov word [invuln], INVULNFRAMES
        ret
hmdie:  call KillMario
hmend:  ret

; ------------------------------------------------------------
; CollectCoins : coin and flag tiles touched by the hitbox
;   in : none
;   out: score, coins, flagtouch
;   registers changed: none
; ------------------------------------------------------------
CollectCoins:
        push ax
        push word [my]
        call TouchRow
        mov ax, [mh]
        shr ax, 1
        add ax, [my]
        push ax
        call TouchRow
        mov ax, [my]
        add ax, [mh]
        dec ax
        push ax
        call TouchRow
        pop ax
        ret

; ------------------------------------------------------------
; TouchRow : test the left and right hitbox edge at y
;   in : y (stack)
;   out: see TouchPoint
;   registers changed: none
; ------------------------------------------------------------
TouchRow:                           ; y
        push bp
        mov bp, sp
        push ax
        mov ax, [mx]
        add ax, 2
        push ax
        push word [bp+4]
        call TouchPoint
        mov ax, [mx]
        add ax, 13
        push ax
        push word [bp+4]
        call TouchPoint
        pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; TouchPoint : collect a coin or touch the flag at a pixel
;   in : px, py (stack)
;   out: working map, score
;   registers changed: none
; ------------------------------------------------------------
TouchPoint:                         ; px, py
        push bp
        mov bp, sp
        push ax
        push bx
        push word [bp+6]
        push word [bp+4]
        call TileIndex
        cmp ax, 0
        jl tpend
        mov bx, ax
        mov al, [workmap+bx]
        cmp al, T_COIN
        jne tp1
        mov byte [workmap+bx], T_SKY
        mov ax, 200
        push ax
        call AddScore
        call AddCoin
        jmp tpend
tp1:    cmp al, T_POLE
        jne tpend
        mov byte [flagtouch], 1
tpend:  pop bx
        pop ax
        pop bp
        ret 4

; ================= MODULE 13: score, lives, HUD =================
; ------------------------------------------------------------
; AddScore : 32-bit score += points (ADD/ADC), clamp 999999
;   in : points (stack)
;   out: score
;   registers changed: none
; ------------------------------------------------------------
AddScore:                           ; points (16 bit), 32 bit score with ADD/ADC
        push bp
        mov bp, sp
        push ax
        mov ax, [bp+4]
        add [score], ax
        adc word [score+2], 0
        cmp word [score+2], MAXSCOREHI    ; clamp to 999999 = 0x000F423F
        jb asend
        ja asclamp
        cmp word [score], MAXSCORELO
        jbe asend
asclamp: mov word [score+2], MAXSCOREHI
        mov word [score], MAXSCORELO
asend:  pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; AddCoin : coins + 1, every 100 give a life
;   in : none
;   out: coins, lives
;   registers changed: none
; ------------------------------------------------------------
AddCoin:
        inc byte [coins]
        cmp byte [coins], COINSFORLIFE
        jb acend
        mov byte [coins], 0
        call AddLife
acend:  ret

; ------------------------------------------------------------
; AddLife : lives + 1, maximum 99
;   in : none
;   out: lives
;   registers changed: none
; ------------------------------------------------------------
AddLife:
        cmp byte [lives], MAXLIVES
        jae alend
        inc byte [lives]
alend:  ret

; ------------------------------------------------------------
; PrintStr : BIOS text (INT 10h/13h) of a zero terminated string
;   in : col, row, string address, colour (stack)
;   out: text on screen
;   registers changed: none
; ------------------------------------------------------------
PrintStr:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push dx
        push di
        push es
        push ds
        pop es
        mov di, [bp+6]
        mov cx, 0xFFFF
        xor al, al
        cld
        repne scasb
        mov ax, 0xFFFF
        sub ax, cx
        dec ax                      ; length
        jz psend
        mov cx, ax
        mov dh, [bp+8]
        mov dl, [bp+10]
        mov bl, [bp+4]
        xor bh, bh
        push bp
        mov bp, [bp+6]
        mov ax, 0x1300
        int 0x10
        pop bp
psend:  pop es
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret 8

; ------------------------------------------------------------
; PrintTable : print a table of col,row,string entries
;   in : table address (stack)
;   out: text on screen
;   registers changed: none
; ------------------------------------------------------------
PrintTable:                         ; table address
        push bp
        mov bp, sp
        push ax
        push si
        mov si, [bp+4]
ptl:    cmp byte [si], 0xFF
        je ptend
        xor ah, ah
        mov al, [si]
        push ax
        mov al, [si+1]
        push ax
        add si, 2
        push si
        mov ax, C_WHITE
        push ax
        call PrintStr
ptskip: cmp byte [si], 0
        je ptnext
        inc si
        jmp ptskip
ptnext: inc si
        jmp ptl
ptend:  pop si
        pop ax
        pop bp
        ret 2

; ------------------------------------------------------------
; PrintNumber : print a 32-bit number as decimal digits, repeated division by 10
;   in : col, row, low word, high word, digits (stack)
;   out: text on screen
;   registers changed: none
; ------------------------------------------------------------
PrintNumber:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        mov cx, [bp+4]
        mov bx, 10
pnl:    mov ax, [bp+6]
        xor dx, dx
        div bx
        mov [bp+6], ax
        mov ax, [bp+8]
        div bx
        mov [bp+8], ax
        add dl, 0x30
        push dx
        loop pnl
        mov si, numbuf
        mov cx, [bp+4]
pnp:    pop dx
        mov [si], dl
        inc si
        loop pnp
        mov byte [si], 0
        push word [bp+12]
        push word [bp+10]
        mov ax, numbuf
        push ax
        mov ax, C_WHITE
        push ax
        call PrintStr
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret 10

; ------------------------------------------------------------
; DrawHUD : HUD strip and hearts into the buffer
;   in : none (hp)
;   out: buffer
;   registers changed: none
; ------------------------------------------------------------
DrawHUD:                            ; graphics part (into the buffer)
        push ax
        xor ax, ax
        push ax
        push ax
        mov ax, SCRW
        push ax
        mov ax, 16
        push ax
        xor ax, ax
        push ax
        call FillRect               ; black HUD strip
        xor ax, ax
        push ax
        mov ax, MAPPX
        push ax
        mov ax, SCRW
        push ax
        mov ax, 8
        push ax
        xor ax, ax
        push ax
        call FillRect               ; black bottom strip
        mov ax, 296
        push ax
        mov ax, 4
        push ax
        mov ax, heartlist
        push ax
        mov ax, C_RED
        push ax
        call DrawRects              ; heart 1 always filled
        mov ax, 310
        push ax
        mov ax, 4
        push ax
        mov ax, heartlist
        push ax
        mov ax, C_DGRAY
        cmp byte [hp], 2
        jne dh1
        mov ax, C_RED
dh1:    push ax
        call DrawRects              ; heart 2 filled only as Super
        pop ax
        ret

; ------------------------------------------------------------
; DrawHUDText : HUD labels and numbers drawn after the flip
;   in : none
;   out: text on screen
;   registers changed: none
; ------------------------------------------------------------
DrawHUDText:                        ; BIOS text drawn on the screen after the flip
        push ax
        mov ax, hudtxt
        push ax
        call PrintTable
        mov ax, 1
        push ax
        push ax
        push word [score]
        push word [score+2]
        mov ax, 6
        push ax
        call PrintNumber
        mov ax, 12
        push ax
        mov ax, 1
        push ax
        mov al, [coins]
        xor ah, ah
        push ax
        xor ax, ax
        push ax
        mov ax, 2
        push ax
        call PrintNumber
        mov ax, 26
        push ax
        mov ax, 1
        push ax
        push word [timeleft]
        xor ax, ax
        push ax
        mov ax, 3
        push ax
        call PrintNumber
        mov ax, 34
        push ax
        mov ax, 1
        push ax
        mov al, [lives]
        xor ah, ah
        push ax
        xor ax, ax
        push ax
        mov ax, 2
        push ax
        call PrintNumber
        pop ax
        ret

; ================= drawing of the game world =================
; ------------------------------------------------------------
; DrawMario : draw Mario (small or super, pose, mirror, blink)
;   in : none
;   out: sprites in buffer
;   registers changed: none
; ------------------------------------------------------------
DrawMario:
        push ax
        push bx
        push cx
        push dx
        cmp word [invuln], 0
        je dmok
        test byte [frame], 1        ; blink while invulnerable
        jnz dmrend
dmok:   xor bx, bx
        cmp byte [onground], 0
        jne dmg
        mov bx, 4                   ; jump pose
        jmp dmp
dmg:    cmp word [mvx], 0
        je dmp
        test byte [frame], 4
        jz dmp
        mov bx, 2                   ; run pose
dmp:    xor cx, cx
        mov cl, [facing]
        mov ax, [mx]
        sub ax, [camerax]
        cmp byte [form], 1
        je dmsup
        push ax
        push word [my]
        push word [smallpose+bx]
        push cx
        call DrawSprite
        jmp dmrend
dmsup:  push ax
        push word [my]
        mov dx, spr_superT
        push dx
        push cx
        call DrawSprite
        mov ax, [mx]
        sub ax, [camerax]
        push ax
        mov dx, [my]
        add dx, 16
        push dx
        push word [superpose+bx]
        push cx
        call DrawSprite
dmrend:  pop dx
        pop cx
        pop bx
        pop ax
        ret

; ------------------------------------------------------------
; DrawWorld : draw a complete frame and show it
;   in : none
;   out: screen
;   registers changed: none
; ------------------------------------------------------------
DrawWorld:
        push ax
        mov ax, C_SKY
        push ax
        call ClearBuffer
        call DrawMap
        call DrawEnemies
        call DrawMario
        call DrawHUD
        call FlipBuffer
        call DrawHUDText
        pop ax
        ret

; ================= MODULE 14: states =================
; ------------------------------------------------------------
; StateTitle : title screen: menu keys, drawing
;   in : none
;   out: state, menusel
;   registers changed: none
; ------------------------------------------------------------
StateTitle:
        push ax
        mov al, [kbpress]
        mov byte [kbpress], 0
        cmp al, SC_UP
        jne ti1
        mov byte [menusel], 0
ti1:    cmp al, SC_DOWN
        jne ti2
        mov byte [menusel], 1
ti2:    cmp al, SC_ESC
        je sttoexit
        cmp al, SC_ENTER
        jne stdraw
        cmp byte [menusel], 0
        jne sttoexit
        call NewGame
        mov byte [state], ST_PLAYING
        jmp stend
sttoexit: mov byte [state], ST_EXIT
        jmp stend
stdraw: mov ax, C_SKY
        push ax
        call ClearBuffer
        xor ax, ax
        push ax
        mov ax, 160
        push ax
        mov ax, SCRW
        push ax
        mov ax, 32
        push ax
        mov ax, C_BROWN
        push ax
        call FillRect
        mov ax, 60
        push ax
        mov ax, 144
        push ax
        mov ax, spr_marioS
        push ax
        xor ax, ax
        push ax
        call DrawSprite
        mov ax, 200
        push ax
        mov ax, 144
        push ax
        mov ax, spr_goomba
        push ax
        xor ax, ax
        push ax
        call DrawSprite
        mov ax, 260
        push ax
        mov ax, 128
        push ax
        mov ax, 6
        push ax
        call DrawTile
        mov ax, 276
        push ax
        mov ax, 128
        push ax
        mov ax, 7
        push ax
        call DrawTile
        mov ax, 260
        push ax
        mov ax, 144
        push ax
        mov ax, 8
        push ax
        call DrawTile
        mov ax, 276
        push ax
        mov ax, 144
        push ax
        mov ax, 9
        push ax
        call DrawTile
        call FlipBuffer
        mov ax, titletxt
        push ax
        call PrintTable
        mov ax, 13
        push ax
        mov al, [menusel]
        xor ah, ah
        shl ax, 1
        add ax, 12
        push ax
        mov ax, arrow
        push ax
        mov ax, C_WHITE
        push ax
        call PrintStr
stend:  pop ax
        ret

; ------------------------------------------------------------
; StatePlaying : one frame of play, in the order of Section 5.13
;   in : none
;   out: everything
;   registers changed: none
; ------------------------------------------------------------
StatePlaying:
        push ax
        mov al, [kbpress]
        mov byte [kbpress], 0
        cmp al, SC_P                ; P
        jne sp1
        mov byte [state], ST_PAUSED
        jmp spend
sp1:    cmp al, SC_ESC                ; Esc
        jne sp2
        mov byte [state], ST_TITLE
        jmp spend
sp2:    inc byte [frame]
        call UpdateMario
        call UpdateEnemies
        call UpdateMushroom
        call CheckEnemies
        call CollectCoins
        call UpdateClock
        cmp byte [state], ST_PLAYING
        jne spdraw
        cmp byte [flagtouch], 0
        je sp3
        call StartWin
        jmp spdraw
sp3:    call UpdateCamera
spdraw: call DrawWorld
spend:  pop ax
        ret

; ------------------------------------------------------------
; StatePaused : frozen game, P resumes, Esc to title
;   in : none
;   out: state
;   registers changed: none
; ------------------------------------------------------------
StatePaused:
        push ax
        mov al, [kbpress]
        mov byte [kbpress], 0
        cmp al, SC_P
        je spresume
        cmp al, SC_ESC
        je sptitle
        mov ax, pausetxt
        push ax
        call PrintTable
        jmp spaend
spresume: mov byte [state], ST_PLAYING
        jmp spaend
sptitle: mov byte [state], ST_TITLE
spaend: pop ax
        ret

; ------------------------------------------------------------
; StateDying : death animation, then life lost or game over
;   in : none
;   out: state, lives
;   registers changed: none
; ------------------------------------------------------------
StateDying:
        push ax
        inc word [dytimer]
        add word [mvy], GRAVITY        ; gravity, no collisions
        mov ax, [mvy]
        add [myf], al
        mov al, ah
        cbw
        adc [my], ax
        call DrawWorld
        cmp word [dytimer], DEATHFRAMES
        jb sdend
        dec byte [lives]
        jz sdover
        mov byte [state], ST_LIFELOST
        mov word [lltimer], LIFELOSTFRAMES
        jmp sdend
sdover: mov byte [state], ST_GAMEOVER
sdend:  pop ax
        ret

; ------------------------------------------------------------
; StateLifeLost : life-lost screen, then restart the level
;   in : none
;   out: state
;   registers changed: none
; ------------------------------------------------------------
StateLifeLost:
        push ax
        xor ax, ax
        push ax
        call ClearBuffer
        mov ax, 152
        push ax
        mov ax, 100
        push ax
        mov ax, spr_marioS
        push ax
        xor ax, ax
        push ax
        call DrawSprite
        call FlipBuffer
        mov ax, lltxt
        push ax
        call PrintTable
        mov ax, 22
        push ax
        mov ax, 13
        push ax
        mov al, [lives]
        xor ah, ah
        push ax
        xor ax, ax
        push ax
        mov ax, 2
        push ax
        call PrintNumber
        dec word [lltimer]
        jnz sllend
        call ResetLevel
        mov byte [state], ST_PLAYING
sllend: pop ax
        ret

; ------------------------------------------------------------
; StateWin : slide down the pole, walk off, time bonus
;   in : none
;   out: state, score
;   registers changed: none
; ------------------------------------------------------------
StateWin:
        push ax
        inc word [wintimer]
        cmp byte [winphase], 0
        jne swwalk
        mov ax, [my]
        add ax, [mh]
        cmp ax, 144                 ; base of the pole
        jge swbase
        add word [my], 2
        jmp swdraw
swbase: mov ax, 144
        sub ax, [mh]
        mov [my], ax
        mov byte [winphase], 1
        mov word [wintimer], 0
        mov byte [onground], 1
        mov byte [facing], 0
        mov word [mvx], 0x200
        jmp swdraw
swwalk: add word [mx], 2
        cmp word [wintimer], 24
        jb swdraw
        mov ax, [timeleft]          ; time bonus: seconds * 50
        mov [endtime], ax
        mov bx, 50
        mul bx
        push ax
        call AddScore
        mov byte [state], ST_COMPLETE
swdraw: call DrawWorld
        pop ax
        ret

; ------------------------------------------------------------
; StateComplete : level complete screen, Enter returns to title
;   in : none
;   out: state
;   registers changed: none
; ------------------------------------------------------------
StateComplete:
        push ax
        mov al, [kbpress]
        mov byte [kbpress], 0
        cmp al, SC_ENTER
        jne scdraw
        mov byte [state], ST_TITLE
        jmp scend
scdraw: xor ax, ax
        push ax
        call ClearBuffer
        call FlipBuffer
        mov ax, cptxt
        push ax
        call PrintTable
        mov ax, 18
        push ax
        mov ax, 8
        push ax
        push word [score]
        push word [score+2]
        mov ax, 6
        push ax
        call PrintNumber
        mov ax, 18
        push ax
        mov ax, 10
        push ax
        mov al, [coins]
        xor ah, ah
        push ax
        xor ax, ax
        push ax
        mov ax, 2
        push ax
        call PrintNumber
        mov ax, 20
        push ax
        mov ax, 12
        push ax
        push word [endtime]
        xor ax, ax
        push ax
        mov ax, 3
        push ax
        call PrintNumber
scend:  pop ax
        ret

; ------------------------------------------------------------
; StateGameOver : game over screen, Enter returns to title
;   in : none
;   out: state
;   registers changed: none
; ------------------------------------------------------------
StateGameOver:
        push ax
        mov al, [kbpress]
        mov byte [kbpress], 0
        cmp al, SC_ENTER
        jne sgdraw
        mov byte [state], ST_TITLE
        jmp sgend
sgdraw: xor ax, ax
        push ax
        call ClearBuffer
        call FlipBuffer
        mov ax, gotxt
        push ax
        call PrintTable
        mov ax, 18
        push ax
        mov ax, 11
        push ax
        push word [score]
        push word [score+2]
        mov ax, 6
        push ax
        call PrintNumber
sgend:  pop ax
        ret

; ================= MODULE 15: reset / death / win =================
; ------------------------------------------------------------
; KillMario : start the death sequence (only while playing)
;   in : none
;   out: state, mvy
;   registers changed: none
; ------------------------------------------------------------
KillMario:
        cmp byte [state], ST_PLAYING
        jne kmend
        mov byte [state], ST_DYING
        mov word [dytimer], 0
        mov word [invuln], 0
        mov byte [onground], 0
        mov word [mvx], 0
        mov word [mvy], 0
        cmp word [my], MAPPX          ; pit death: no hop
        jge kmend
        mov word [mvy], DEATHHOP      ; hop up about 48 pixels
kmend:  ret

; ------------------------------------------------------------
; StartWin : flag touched: flag points, snap to pole, win state
;   in : none
;   out: score, state
;   registers changed: none
; ------------------------------------------------------------
StartWin:
        push ax
        push bx
        push cx
        mov ax, [my]
        add ax, [mh]
        dec ax
        mov cl, TILESHIFT
        shr ax, cl                  ; row of the feet
        cmp ax, 2
        jge sw1
        mov ax, 2
sw1:    cmp ax, 8
        jle sw2
        mov ax, 8
sw2:    sub ax, 2
        shl ax, 1
        mov bx, ax
        mov ax, [flagtable+bx]
        push ax
        call AddScore
        mov ax, [mx]
        add ax, 8
        and ax, 0xFFF0
        mov [mx], ax                ; snap to the pole
        mov byte [mxf], 0
        mov word [mvx], 0
        mov word [mvy], 0
        mov byte [winphase], 0
        mov word [wintimer], 0
        mov byte [flagtouch], 0
        mov byte [state], ST_WIN
        pop cx
        pop bx
        pop ax
        ret

; ------------------------------------------------------------
; ResetLevel : map, enemies, mushroom, clock, camera and Mario back to start
;   in : none
;   out: all level variables
;   registers changed: none
; ------------------------------------------------------------
ResetLevel:
        push ax
        push cx
        push si
        push di
        push es
        call ResetMap
        push ds
        pop es
        mov si, enemyinit
        mov di, enemies
        mov cx, 128
        cld
        rep movsb
        mov byte [mushrec], 0
        mov word [timeleft], LEVELTIME
        mov word [tickcount], 0
        mov word [camerax], 0
        mov word [mx], 32
        mov byte [mxf], 0
        mov word [my], 144
        mov byte [myf], 0
        mov word [mvx], 0
        mov word [mvy], 0
        mov word [mh], 16
        mov byte [form], 0
        mov byte [hp], 1
        mov byte [onground], 0
        mov byte [jumplock], 0
        mov byte [facing], 0
        mov byte [chain], 0
        mov word [invuln], 0
        mov byte [flagtouch], 0
        mov byte [kbpress], 0
        pop es
        pop di
        pop si
        pop cx
        pop ax
        ret

; ------------------------------------------------------------
; NewGame : score, coins, lives reset, then ResetLevel
;   in : none
;   out: score, coins, lives
;   registers changed: none
; ------------------------------------------------------------
NewGame:
        mov word [score], 0
        mov word [score+2], 0
        mov byte [coins], 0
        mov byte [lives], STARTLIVES
        call ResetLevel
        ret
