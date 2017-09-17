// The result of translation follows.  Its copyright status should be
// considered unchanged from the original VHDL.

// This file is copyright by Grant Searle 2014
// You are free to use this file in your own projects but must never charge for it nor use it without
// acknowledgement.
// Please ask permission from Grant Searle before republishing elsewhere.
// If you use this file or any part of it, please add an acknowledgement to myself and
// a link back to my main web site http://searle.hostei.com/grant/    
// and to the "multicomp" page at http://searle.hostei.com/grant/Multicomp/index.html
//
// Please check on the above web pages to see if there are any updates before using this file.
// If for some reason the page is no longer available, please search for "Grant Searle"
// on the internet to see if I have moved to another web hosting service.
//
// Grant Searle
// eMail address available on my main web page link above.
// no timescale needed

module SBCTextDisplayRGB
  (
   input            n_reset,
   input            clk,
   input            n_wr,
   input            n_rd,
   input            regSel,
   input [7:0]      dataIn,
   output reg [7:0] dataOut,
   output           n_int,
   output           n_rts,
   // RGB video signals
   output reg       videoR0,
   output reg       videoR1,
   output reg       videoG0,
   output reg       videoG1,
   output reg       videoB0,
   output reg       videoB1,
   output reg       hSync,
   output reg       vSync,
   // Monochrome video signals
   output reg       video,
   output           sync,
   // Keyboard signals
   inout            ps2Clk,
   inout            ps2Data,
   // FN keys passed out as general signals (momentary and toggled versions)
   output [12:0]    FNkeys,
   output [12:0]    FNtoggledKeys
   );
   
   parameter [31:0] EXTENDED_CHARSET=0;
   parameter [31:0] COLOUR_ATTS_ENABLED=0;
   parameter [31:0] VERT_CHARS=25;
   parameter [31:0] HORIZ_CHARS=80;
   parameter [31:0] CLOCKS_PER_SCANLINE=1600;
   parameter [31:0] DISPLAY_TOP_SCANLINE=35 + 40;
   parameter [31:0] DISPLAY_LEFT_CLOCK=288;
   parameter [31:0] VERT_SCANLINES=525;
   parameter [31:0] VSYNC_SCANLINES=2;
   parameter [31:0] HSYNC_CLOCKS=192;
   parameter [31:0] VERT_PIXEL_SCANLINES=2;
   parameter [31:0] CLOCKS_PER_PIXEL=2;
   parameter H_SYNC_ACTIVE=1'b0;
   parameter V_SYNC_ACTIVE=1'b0;
   parameter [7:0] DEFAULT_ATT=8'b00001111;
   parameter [7:0] ANSI_DEFAULT_ATT=8'b00000111;
   // background iBGR | foreground iBGR (i=intensity)
   
   //VGA 640x400
   //constant VERT_CHARS : integer := 25;
   //constant HORIZ_CHARS : integer := 80;
   //constant CLOCKS_PER_SCANLINE : integer := 1600;
   //constant DISPLAY_TOP_SCANLINE : integer := 35;
   //constant DISPLAY_LEFT_CLOCK : integer := 288;
   //constant VERT_SCANLINES : integer := 448;
   //constant VSYNC_SCANLINES : integer := 2;
   //constant HSYNC_CLOCKS : integer := 192;
   //constant VERT_PIXEL_SCANLINES : integer := 2;
   //constant CLOCKS_PER_PIXEL : integer := 2; -- min = 2
   //constant H_SYNC_ACTIVE : std_logic := '0';
   //constant V_SYNC_ACTIVE : std_logic := '1';


   parameter HORIZ_CHAR_MAX = HORIZ_CHARS-1;
   parameter VERT_CHAR_MAX = VERT_CHARS-1;
   parameter CHARS_PER_SCREEN = HORIZ_CHARS*VERT_CHARS;

   reg [12:0]       FNkeysSig = 0;
   reg [12:0]       FNtoggledKeysSig = 0;

   reg              vActive  = 1'b0;
   reg              hActive  = 1'b0;

   reg [3:0]        pixelClockCount = 0;
   reg [2:0]        pixelCount = 0; 
   
   reg [11:0]       horizCount = 0; 
   reg [9:0]        vertLineCount = 0; 

   reg [4:0]        charVert = 0;   
   reg [3:0]        charScanLine = 0; 

   reg [6:0]        charHoriz;
   reg [3:0]        charBit; 

   reg [4:0]        cursorVert = 0;
   reg [6:0]        cursorHoriz = 0;

   reg [4:0]        cursorVertRestore = 0;
   reg [6:0]        cursorHorizRestore = 0;
   
   reg [4:0]        savedCursorVert = 0;
   reg [6:0]        savedCursorHoriz =0;
   
   reg [10:0]        startAddr = 0; 
   wire [10:0]       cursAddr;
        
   wire [10:0]       dispAddr;
   wire [10:0]       charAddr;

   wire [7:0]        dispCharData;
   reg [7:0]         dispCharWRData;
   wire [7:0]        dispCharRDData;
   
   wire [7:0]        dispAttData;
   reg [7:0]         dispAttWRData = DEFAULT_ATT; // iBGR(back) iBGR(text)
   wire [7:0]        dispAttRDData;
   
   wire [7:0]        charData;

   reg               cursorOn  = 1'b1;
   reg               dispWR = 1'b0;
   reg [25:0]        cursBlinkCount;
   reg [25:0]        kbWatchdogTimer = 0;
   reg [25:0]        kbWriteTimer = 0;

   wire              n_int_internal = 1'b1;
   
   wire [7:0]        statusReg; 
   reg [7:0]         controlReg = 8'h00;
    
   reg [6:0]         kbBuffer[0 : 7];

   reg [3:0]         kbInPointer = 0;
   reg [3:0]         kbReadPointer = 0;
   wire [3:0]        kbBuffCount;
   reg               dispByteWritten = 1'b0;
   reg               dispByteSent = 1'b0;
   
   reg [7:0]         dispByteLatch;

   parameter
     idle        = 0,
     dispWrite   = 1,
     dispNextLoc = 2,
     clearLine   = 3,
     clearL2     = 4,     
     clearScreen = 5,
     clearS2     = 6,
     clearChar   = 7,
     clearC2     = 8,
     insertLine  = 9,
     ins2        = 10,
     ins3        = 11,
     deleteLine  = 12,
     del2        = 13,
     del3        = 14;
   
   reg [3:0]         dispState = idle;

   parameter
     none                       = 0,
     waitForLeftBracket         = 1,
     processingParams           = 2,
     processingAdditionalParams = 3;
   
   reg [1:0]         nextState = none;
   
   reg [6:0]         param1 = 0;
   reg [6:0]         param2 = 0;
   reg [6:0]         param3 = 0;
   reg [6:0]         param4 = 0;
   reg [2:0]         paramCount = 0;

   reg               attInverse = 1'b0;
   reg               attBold = DEFAULT_ATT[3];

   reg [7:0]         ps2Byte; 
   reg [7:0]         ps2PreviousByte; 
   reg [6:0]         ps2ConvertedByte; 
   reg [3:0]         ps2ClkCount = 0;
   reg [4:0]         ps2WriteClkCount = 0;
   reg [7:0]         ps2WriteByte = 8'hff; 
   reg [7:0]         ps2WriteByte2 = 8'hff; 
   reg               ps2PrevClk = 1'b1;
   reg [5:0]         ps2ClkFilter = 0; 
   reg               ps2ClkFiltered = 1'b1;

   reg               ps2Shift = 1'b0;
   reg               ps2Ctrl = 1'b0;
   reg               ps2Caps = 1'b1;
   reg               ps2Num = 1'b0;
   reg               ps2Scroll = 1'b0;
   
   reg               ps2DataOut = 1'b1;
   reg               ps2ClkOut = 1'b1;
   wire              ps2DataIn;
   wire              ps2ClkIn;
              
   reg               n_kbWR = 1'b1;
   reg               kbWRParity = 1'b0;
   
   // UK KEYBOARD MAPPING (except for shift-3 = "#")
   //Original 8-bit HEX values
   // constant kbUnshifted : kbDataArray :=
   // (
   // --0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
   // x"00",x"19",x"00",x"00",x"13",x"11",x"12",x"1C",x"00",x"1A",x"18",x"16",x"00",x"09",x"60",x"00", -- 0
   // x"00",x"00",x"00",x"00",x"00",x"71",x"31",x"00",x"00",x"00",x"7A",x"73",x"61",x"77",x"32",x"00", -- 1
   // x"00",x"63",x"78",x"64",x"65",x"34",x"33",x"00",x"00",x"20",x"76",x"66",x"74",x"72",x"35",x"00", -- 2
   // x"00",x"6E",x"62",x"68",x"67",x"79",x"36",x"00",x"00",x"00",x"6D",x"6A",x"75",x"37",x"38",x"00", -- 3
   // x"00",x"2C",x"6B",x"69",x"6F",x"30",x"39",x"00",x"00",x"2E",x"2F",x"6C",x"3B",x"70",x"2D",x"00", -- 4
   // x"00",x"00",x"27",x"00",x"5B",x"3D",x"00",x"00",x"00",x"00",x"0D",x"5D",x"00",x"00",x"00",x"00", -- 5
   // x"00",x"00",x"00",x"00",x"00",x"00",x"08",x"00",x"00",x"31",x"00",x"34",x"37",x"00",x"00",x"00", -- 6
   // x"30",x"2E",x"32",x"35",x"36",x"38",x"03",x"00",x"1B",x"2B",x"33",x"2D",x"2A",x"39",x"00",x"00", -- 7
   // x"00",x"00",x"00",x"17"
   // );
   // constant kbShifted : kbDataArray :=
   // (
   // --0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
   // x"00",x"19",x"00",x"00",x"13",x"11",x"12",x"1C",x"00",x"1A",x"18",x"16",x"00",x"09",x"00",x"00", -- 0
   // x"00",x"00",x"00",x"00",x"00",x"51",x"21",x"00",x"00",x"00",x"5A",x"53",x"41",x"57",x"22",x"00", -- 1
   // x"00",x"43",x"58",x"44",x"45",x"24",x"23",x"00",x"00",x"20",x"56",x"46",x"54",x"52",x"25",x"00", -- 2
   // x"00",x"4E",x"42",x"48",x"47",x"59",x"5E",x"00",x"00",x"00",x"4D",x"4A",x"55",x"26",x"2A",x"00", -- 3
   // x"00",x"3C",x"4B",x"49",x"4F",x"29",x"28",x"00",x"00",x"3E",x"3F",x"4C",x"3A",x"50",x"5F",x"00", -- 4
   // x"00",x"00",x"40",x"00",x"7B",x"2B",x"00",x"00",x"00",x"00",x"0D",x"7D",x"00",x"00",x"00",x"00", -- 5
   // x"00",x"00",x"00",x"00",x"00",x"00",x"08",x"00",x"00",x"31",x"00",x"34",x"37",x"00",x"00",x"00", -- 6
   // x"30",x"2E",x"32",x"35",x"36",x"38",x"0C",x"00",x"1B",x"2B",x"33",x"2D",x"2A",x"39",x"00",x"00", -- 7
   // x"00",x"00",x"00",x"17"
   // );
   
   //  7 bits to reduce logic count
   reg [6:0]         kbUnshifted[0 : 131];
   reg [6:0]         kbShifted[0 : 131];

   initial
     begin
        kbUnshifted[0] <= 7'b0000000;
        kbUnshifted[1] <= 7'b0011001;
        kbUnshifted[2] <= 7'b0000000;
        kbUnshifted[3] <= 7'b0000000;
        kbUnshifted[4] <= 7'b0010011;
        kbUnshifted[5] <= 7'b0010001;
        kbUnshifted[6] <= 7'b0010010;
        kbUnshifted[7] <= 7'b0011100;
        kbUnshifted[8] <= 7'b0000000;
        kbUnshifted[9] <= 7'b0011010;
        kbUnshifted[10] <= 7'b0011000;
        kbUnshifted[11] <= 7'b0010110;
        kbUnshifted[12] <= 7'b0000000;
        kbUnshifted[13] <= 7'b0001001;
        kbUnshifted[14] <= 7'b1100000;
        kbUnshifted[15] <= 7'b0000000;        
        kbUnshifted[16] <= 7'b0000000;
        kbUnshifted[17] <= 7'b0000000;
        kbUnshifted[18] <= 7'b0000000;
        kbUnshifted[19] <= 7'b0000000;
        kbUnshifted[20] <= 7'b0000000;
        kbUnshifted[21] <= 7'b1110001;
        kbUnshifted[22] <= 7'b0110001;
        kbUnshifted[23] <= 7'b0000000;
        kbUnshifted[24] <= 7'b0000000;
        kbUnshifted[25] <= 7'b0000000;
        kbUnshifted[26] <= 7'b1111010;
        kbUnshifted[27] <= 7'b1110011;
        kbUnshifted[28] <= 7'b1100001;
        kbUnshifted[29] <= 7'b1110111;
        kbUnshifted[30] <= 7'b0110010;
        kbUnshifted[31] <= 7'b0000000;
        kbUnshifted[32] <= 7'b0000000;
        kbUnshifted[33] <= 7'b1100011;
        kbUnshifted[34] <= 7'b1111000;
        kbUnshifted[35] <= 7'b1100100;
        kbUnshifted[36] <= 7'b1100101;
        kbUnshifted[37] <= 7'b0110100;
        kbUnshifted[38] <= 7'b0110011;
        kbUnshifted[39] <= 7'b0000000;
        kbUnshifted[40] <= 7'b0000000;
        kbUnshifted[41] <= 7'b0100000;
        kbUnshifted[42] <= 7'b1110110;
        kbUnshifted[43] <= 7'b1100110;
        kbUnshifted[44] <= 7'b1110100;
        kbUnshifted[45] <= 7'b1110010;
        kbUnshifted[46] <= 7'b0110101;
        kbUnshifted[47] <= 7'b0000000;
        kbUnshifted[48] <= 7'b0000000;
        kbUnshifted[49] <= 7'b1101110;
        kbUnshifted[50] <= 7'b1100010;
        kbUnshifted[51] <= 7'b1101000;
        kbUnshifted[52] <= 7'b1100111;
        kbUnshifted[53] <= 7'b1111001;
        kbUnshifted[54] <= 7'b0110110;
        kbUnshifted[55] <= 7'b0000000;
        kbUnshifted[56] <= 7'b0000000;
        kbUnshifted[57] <= 7'b0000000;
        kbUnshifted[58] <= 7'b1101101;
        kbUnshifted[59] <= 7'b1101010;
        kbUnshifted[60] <= 7'b1110101;
        kbUnshifted[61] <= 7'b0110111;
        kbUnshifted[62] <= 7'b0111000;
        kbUnshifted[63] <= 7'b0000000;
        kbUnshifted[64] <= 7'b0000000;
        kbUnshifted[65] <= 7'b0101100;
        kbUnshifted[66] <= 7'b1101011;
        kbUnshifted[67] <= 7'b1101001;
        kbUnshifted[68] <= 7'b1101111;
        kbUnshifted[69] <= 7'b0110000;
        kbUnshifted[70] <= 7'b0111001;
        kbUnshifted[71] <= 7'b0000000;
        kbUnshifted[72] <= 7'b0000000;
        kbUnshifted[73] <= 7'b0101110;
        kbUnshifted[74] <= 7'b0101111;
        kbUnshifted[75] <= 7'b1101100;
        kbUnshifted[76] <= 7'b0111011;
        kbUnshifted[77] <= 7'b1110000;
        kbUnshifted[78] <= 7'b0101101;
        kbUnshifted[79] <= 7'b0000000;
        kbUnshifted[80] <= 7'b0000000;
        kbUnshifted[81] <= 7'b0000000;
        kbUnshifted[82] <= 7'b0100111;
        kbUnshifted[83] <= 7'b0000000;
        kbUnshifted[84] <= 7'b1011011;
        kbUnshifted[85] <= 7'b0111101;
        kbUnshifted[86] <= 7'b0000000;
        kbUnshifted[87] <= 7'b0000000;
        kbUnshifted[88] <= 7'b0000000;
        kbUnshifted[89] <= 7'b0000000;
        kbUnshifted[90] <= 7'b0001101;
        kbUnshifted[91] <= 7'b1011101;
        kbUnshifted[92] <= 7'b0000000;
        kbUnshifted[93] <= 7'b0000000;
        kbUnshifted[94] <= 7'b0000000;
        kbUnshifted[95] <= 7'b0000000;
        kbUnshifted[96] <= 7'b0000000;
        kbUnshifted[97] <= 7'b0000000;
        kbUnshifted[98] <= 7'b0000000;
        kbUnshifted[99] <= 7'b0000000;
        kbUnshifted[100] <= 7'b0000000;
        kbUnshifted[101] <= 7'b0000000;
        kbUnshifted[102] <= 7'b0001000;
        kbUnshifted[103] <= 7'b0000000;
        kbUnshifted[104] <= 7'b0000000;
        kbUnshifted[105] <= 7'b0110001;
        kbUnshifted[106] <= 7'b0000000;
        kbUnshifted[107] <= 7'b0110100;
        kbUnshifted[108] <= 7'b0110111;
        kbUnshifted[109] <= 7'b0000000;
        kbUnshifted[110] <= 7'b0000000;
        kbUnshifted[111] <= 7'b0000000;
        kbUnshifted[112] <= 7'b0110000;
        kbUnshifted[113] <= 7'b0101110;
        kbUnshifted[114] <= 7'b0110010;
        kbUnshifted[115] <= 7'b0110101;
        kbUnshifted[116] <= 7'b0110110;
        kbUnshifted[117] <= 7'b0111000;
        kbUnshifted[118] <= 7'b0000011;
        kbUnshifted[119] <= 7'b0000000;
        kbUnshifted[120] <= 7'b0011011;
        kbUnshifted[121] <= 7'b0101011;
        kbUnshifted[122] <= 7'b0110011;
        kbUnshifted[123] <= 7'b0101101;
        kbUnshifted[124] <= 7'b0101010;
        kbUnshifted[125] <= 7'b0111001;
        kbUnshifted[126] <= 7'b0000000;
        kbUnshifted[127] <= 7'b0000000;
        kbUnshifted[128] <= 7'b0000000;
        kbUnshifted[129] <= 7'b0000000;
        kbUnshifted[130] <= 7'b0000000;
        kbUnshifted[131] <= 7'b0010111;
     end


   initial
     begin
        kbShifted[0] <= 7'b0000000;
        kbShifted[1] <= 7'b0011001;
        kbShifted[2] <= 7'b0000000;
        kbShifted[3] <= 7'b0000000;
        kbShifted[4] <= 7'b0010011;
        kbShifted[5] <= 7'b0010001;
        kbShifted[6] <= 7'b0010010;
        kbShifted[7] <= 7'b0011100;
        kbShifted[8] <= 7'b0000000;
        kbShifted[9] <= 7'b0011010;
        kbShifted[10] <= 7'b0011000;
        kbShifted[11] <= 7'b0010110;
        kbShifted[12] <= 7'b0000000;
        kbShifted[13] <= 7'b0001001;
        kbShifted[14] <= 7'b0000000;
        kbShifted[15] <= 7'b0000000;
        kbShifted[16] <= 7'b0000000;
        kbShifted[17] <= 7'b0000000;
        kbShifted[18] <= 7'b0000000;
        kbShifted[19] <= 7'b0000000;
        kbShifted[20] <= 7'b0000000;
        kbShifted[21] <= 7'b1010001;
        kbShifted[22] <= 7'b0100001;
        kbShifted[23] <= 7'b0000000;
        kbShifted[24] <= 7'b0000000;
        kbShifted[25] <= 7'b0000000;
        kbShifted[26] <= 7'b1011010;
        kbShifted[27] <= 7'b1010011;
        kbShifted[28] <= 7'b1000001;
        kbShifted[29] <= 7'b1010111;
        kbShifted[30] <= 7'b0100010;
        kbShifted[31] <= 7'b0000000;
        kbShifted[32] <= 7'b0000000;
        kbShifted[33] <= 7'b1000011;
        kbShifted[34] <= 7'b1011000;
        kbShifted[35] <= 7'b1000100;
        kbShifted[36] <= 7'b1000101;
        kbShifted[37] <= 7'b0100100;
        kbShifted[38] <= 7'b0100011;
        kbShifted[39] <= 7'b0000000;
        kbShifted[40] <= 7'b0000000;
        kbShifted[41] <= 7'b0100000;
        kbShifted[42] <= 7'b1010110;
        kbShifted[43] <= 7'b1000110;
        kbShifted[44] <= 7'b1010100;
        kbShifted[45] <= 7'b1010010;
        kbShifted[46] <= 7'b0100101;
        kbShifted[47] <= 7'b0000000;
        kbShifted[48] <= 7'b0000000;
        kbShifted[49] <= 7'b1001110;
        kbShifted[50] <= 7'b1000010;
        kbShifted[51] <= 7'b1001000;
        kbShifted[52] <= 7'b1000111;
        kbShifted[53] <= 7'b1011001;
        kbShifted[54] <= 7'b1011110;
        kbShifted[55] <= 7'b0000000;
        kbShifted[56] <= 7'b0000000;
        kbShifted[57] <= 7'b0000000;
        kbShifted[58] <= 7'b1001101;
        kbShifted[59] <= 7'b1001010;
        kbShifted[60] <= 7'b1010101;
        kbShifted[61] <= 7'b0100110;
        kbShifted[62] <= 7'b0101010;
        kbShifted[63] <= 7'b0000000;
        kbShifted[64] <= 7'b0000000;
        kbShifted[65] <= 7'b0111100;
        kbShifted[66] <= 7'b1001011;
        kbShifted[67] <= 7'b1001001;
        kbShifted[68] <= 7'b1001111;
        kbShifted[69] <= 7'b0101001;
        kbShifted[70] <= 7'b0101000;
        kbShifted[71] <= 7'b0000000;
        kbShifted[72] <= 7'b0000000;
        kbShifted[73] <= 7'b0111110;
        kbShifted[74] <= 7'b0111111;
        kbShifted[75] <= 7'b1001100;
        kbShifted[76] <= 7'b0111010;
        kbShifted[77] <= 7'b1010000;
        kbShifted[78] <= 7'b1011111;
        kbShifted[79] <= 7'b0000000;
        kbShifted[80] <= 7'b0000000;
        kbShifted[81] <= 7'b0000000;
        kbShifted[82] <= 7'b1000000;
        kbShifted[83] <= 7'b0000000;
        kbShifted[84] <= 7'b1111011;
        kbShifted[85] <= 7'b0101011;
        kbShifted[86] <= 7'b0000000;
        kbShifted[87] <= 7'b0000000;
        kbShifted[88] <= 7'b0000000;
        kbShifted[89] <= 7'b0000000;
        kbShifted[90] <= 7'b0001101;
        kbShifted[91] <= 7'b1111101;
        kbShifted[92] <= 7'b0000000;
        kbShifted[93] <= 7'b0000000;
        kbShifted[94] <= 7'b0000000;
        kbShifted[95] <= 7'b0000000;
        kbShifted[96] <= 7'b0000000;
        kbShifted[97] <= 7'b0000000;
        kbShifted[98] <= 7'b0000000;
        kbShifted[99] <= 7'b0000000;
        kbShifted[100] <= 7'b0000000;
        kbShifted[101] <= 7'b0000000;
        kbShifted[102] <= 7'b0001000;
        kbShifted[103] <= 7'b0000000;
        kbShifted[104] <= 7'b0000000;
        kbShifted[105] <= 7'b0110001;
        kbShifted[106] <= 7'b0000000;
        kbShifted[107] <= 7'b0110100;
        kbShifted[108] <= 7'b0110111;
        kbShifted[109] <= 7'b0000000;
        kbShifted[110] <= 7'b0000000;
        kbShifted[111] <= 7'b0000000;
        kbShifted[112] <= 7'b0110000;
        kbShifted[113] <= 7'b0101110;
        kbShifted[114] <= 7'b0110010;
        kbShifted[115] <= 7'b0110101;
        kbShifted[116] <= 7'b0110110;
        kbShifted[117] <= 7'b0111000;
        kbShifted[118] <= 7'b0001100;
        kbShifted[119] <= 7'b0000000;
        kbShifted[120] <= 7'b0011011;
        kbShifted[121] <= 7'b0101011;
        kbShifted[122] <= 7'b0110011;
        kbShifted[123] <= 7'b0101101;
        kbShifted[124] <= 7'b0101010;
        kbShifted[125] <= 7'b0111001;
        kbShifted[126] <= 7'b0000000;
        kbShifted[127] <= 7'b0000000;
        kbShifted[128] <= 7'b0000000;
        kbShifted[129] <= 7'b0000000;
        kbShifted[130] <= 7'b0000000;
        kbShifted[131] <= 7'b0010111;
     end        
   
   // DISPLAY ROM AND RAM
   
   generate
      if (EXTENDED_CHARSET == 1)
        ROM #(11, 8, "../mem/CGAFontBold.mem") fontRom // 256 chars (2K)
          (
           .address(charAddr),
           .clock(clk),
           .q(charData)
           );
      else
        ROM #(10, 8, "../mem/CGAFontBoldReduced.mem") fontRom  // 128 chars (1K)
          (
           .address(charAddr[9:0]),
           .clock(clk),
           .q(charData)
           );        
   endgenerate

   generate
      if (CHARS_PER_SCREEN >1024)
        DisplayRam #(11,8) dispCharRam // For 80x25 display character storage
          (
           .clock(clk),
           .address_b(cursAddr),
           .data_b(dispCharWRData),
           .q_b(dispCharRDData),
           .wren_b(dispWR),
           .address_a(dispAddr),
           .data_a(8'h00),
           .q_a(dispCharData),
           .wren_a(1'b0)
           );
      else
        DisplayRam #(10,8) dispCharRam  // For 40x25 display character storage
          (
           .clock(clk),
           .address_b(cursAddr[9:0]),
           .data_b(dispCharWRData),
           .q_b(dispCharRDData),
           .wren_b(dispWR),
           .address_a(dispAddr[9:0]),
           .data_a(8'h00),
           .q_a(dispCharData),
           .wren_a(1'b0)
           );
   endgenerate
   
   generate
      if (COLOUR_ATTS_ENABLED == 1)
        if (CHARS_PER_SCREEN > 1024)
          DisplayRam #(11,8) dispAttRam  // For 80x25 display attribute storage
            (
             .clock(clk),
             .address_b(cursAddr),
             .data_b(dispAttWRData),
             .q_b(dispAttRDData),
             .wren_b(dispWR),
             .address_a(dispAddr),
             .data_a(8'h00),
             .q_a(dispAttData),
             .wren_a(1'b0)
             );
        else
          DisplayRam #(10,8) dispAttRam  // For 4x25 display attribute storage
            (
             .clock(clk),
             .address_b(cursAddr[9:0]),
             .data_b(dispAttWRData),
             .q_b(dispAttRDData),
             .wren_b(dispWR),
             .address_a(dispAddr[9:0]),
             .data_a(8'h00),
             .q_a(dispAttData),
             .wren_a(1'b0)
             );
      else
        assign dispAttData = dispAttWRData; // If no attribute RAM then two colour output on RGB pins as defined by default/esc sequence
   endgenerate
   
      
   assign FNkeys = FNkeysSig;
   assign FNtoggledKeys = FNtoggledKeysSig;
   assign charAddr = {dispCharData,charScanLine[VERT_PIXEL_SCANLINES + 1:VERT_PIXEL_SCANLINES - 1]};
   assign dispAddr = ((startAddr + charHoriz + ((charVert * HORIZ_CHARS)))) % CHARS_PER_SCREEN;
   assign cursAddr = ((startAddr + cursorHoriz + ((cursorVert * HORIZ_CHARS)))) % CHARS_PER_SCREEN;
   assign sync = vSync & hSync;
   // composite sync for mono video out 
   // SCREEN RENDERING
   always @(negedge clk) begin
      if(horizCount < CLOCKS_PER_SCANLINE) begin
         horizCount <= horizCount + 1;
         if((horizCount < DISPLAY_LEFT_CLOCK) || (horizCount > ((DISPLAY_LEFT_CLOCK + HORIZ_CHARS * CLOCKS_PER_PIXEL * 8)))) begin
            hActive <= 1'b0;
            pixelClockCount <= {4{1'b0}};
            charHoriz <= 0;
         end
         else begin
            hActive <= 1'b1;
         end
      end
      else begin
         horizCount <= {12{1'b0}};
         pixelCount <= {3{1'b0}};
         charHoriz <= 0;
         if(vertLineCount > ((VERT_SCANLINES - 1))) begin
            vertLineCount <= {10{1'b0}};
         end
         else begin
            if(vertLineCount < DISPLAY_TOP_SCANLINE || vertLineCount > ((DISPLAY_TOP_SCANLINE + 8 * VERT_PIXEL_SCANLINES * VERT_CHARS - 1))) begin
               vActive <= 1'b0;
               charVert <= 0;
               charScanLine <= {4{1'b0}};
            end
            else begin
               vActive <= 1'b1;
               if(charScanLine == ((VERT_PIXEL_SCANLINES * 8 - 1))) begin
                  charScanLine <= {4{1'b0}};
                  charVert <= charVert + 1;
               end
               else begin
                  if(vertLineCount != DISPLAY_TOP_SCANLINE) begin
                     charScanLine <= charScanLine + 1;
                  end
               end
            end
            vertLineCount <= vertLineCount + 1;
         end
      end
      if(horizCount < HSYNC_CLOCKS) begin
         hSync <= H_SYNC_ACTIVE;
      end
      else begin
         hSync <=  ~H_SYNC_ACTIVE;
      end
      if(vertLineCount < VSYNC_SCANLINES) begin
         vSync <= V_SYNC_ACTIVE;
      end
      else begin
         vSync <=  ~V_SYNC_ACTIVE;
      end
      if(hActive == 1'b1 && vActive == 1'b1) begin
         if(pixelClockCount < ((CLOCKS_PER_PIXEL - 1))) begin
            pixelClockCount <= pixelClockCount + 1;
         end
         else begin
            if(cursorOn == 1'b1 && cursorVert == charVert && cursorHoriz == charHoriz && charScanLine == ((VERT_PIXEL_SCANLINES * 8 - 1))) begin
               // Cursor (use current colour because cursor cell not yet written to)
               if(dispAttData[3] == 1'b1) begin
                  // BRIGHT
                  videoR0 <= dispAttWRData[0];
                  videoG0 <= dispAttWRData[1];
                  videoB0 <= dispAttWRData[2];
               end
               else begin
                  videoR0 <= 1'b0;
                  videoG0 <= 1'b0;
                  videoB0 <= 1'b0;
               end
               videoR1 <= dispAttWRData[0];
               videoG1 <= dispAttWRData[1];
               videoB1 <= dispAttWRData[2];
               video <= 1'b1;
               // Monochrome video out
            end
            else begin
               if(charData[7 - pixelCount] == 1'b1) begin
                  // Foreground
                  if(dispAttData[3:0] == 4'b1000) begin
                     // special case = GREY
                     videoR0 <= 1'b1;
                     videoG0 <= 1'b1;
                     videoB0 <= 1'b1;
                     videoR1 <= 1'b0;
                     videoG1 <= 1'b0;
                     videoB1 <= 1'b0;
                  end
                  else begin
                     if(dispAttData[3] == 1'b1) begin
                        // BRIGHT
                        videoR0 <= dispAttData[0];
                        videoG0 <= dispAttData[1];
                        videoB0 <= dispAttData[2];
                     end
                     else begin
                        videoR0 <= 1'b0;
                        videoG0 <= 1'b0;
                        videoB0 <= 1'b0;
                     end
                     videoR1 <= dispAttData[0];
                     videoG1 <= dispAttData[1];
                     videoB1 <= dispAttData[2];
                  end
               end
               else begin
                  // Background
                  if(dispAttData[7:4] == 4'b1000) begin
                     // special case = GREY
                     videoR0 <= 1'b1;
                     videoG0 <= 1'b1;
                     videoB0 <= 1'b1;
                     videoR1 <= 1'b0;
                     videoG1 <= 1'b0;
                     videoB1 <= 1'b0;
                  end
                  else begin
                     if(dispAttData[7] == 1'b1) begin
                        // BRIGHT
                        videoR0 <= dispAttData[4];
                        videoG0 <= dispAttData[5];
                        videoB0 <= dispAttData[6];
                     end
                     else begin
                        videoR0 <= 1'b0;
                        videoG0 <= 1'b0;
                        videoB0 <= 1'b0;
                     end
                     videoR1 <= dispAttData[4];
                     videoG1 <= dispAttData[5];
                     videoB1 <= dispAttData[6];
                  end
               end
               video <= charData[7 - pixelCount];
               // Monochrome video out
            end
            pixelClockCount <= {4{1'b0}};
            if(pixelCount == 7) begin
               charHoriz <= charHoriz + 1;
            end
            pixelCount <= pixelCount + 1;
         end
      end
      else begin
         videoR0 <= 1'b0;
         videoG0 <= 1'b0;
         videoB0 <= 1'b0;
         videoR1 <= 1'b0;
         videoG1 <= 1'b0;
         videoB1 <= 1'b0;
         video <= 1'b0;
         // Monochrome video out
      end
   end
   
   // Hardware cursor blink
   always @(posedge clk) begin
      if(cursBlinkCount < 49999999) begin
         cursBlinkCount <= cursBlinkCount + 1;
      end
      else begin
         cursBlinkCount <= {26{1'b0}};
      end
      if(cursBlinkCount < 25000000) begin
         cursorOn <= 1'b0;
      end
      else begin
         cursorOn <= 1'b1;
      end
   end
   
   // minimal 6850 compatibility
   assign statusReg[0] = kbInPointer == kbReadPointer ? 1'b0 : 1'b1;
   assign statusReg[1] = dispByteWritten == dispByteSent ? 1'b1 : 1'b0;
   assign statusReg[2] = 1'b0;
   //n_dcd;
   assign statusReg[3] = 1'b0;
   assign statusReg[6:4] = 3'b000;
   //n_cts;
   assign statusReg[7] =  ~((n_int_internal));
   // interrupt mask
   assign n_int = n_int_internal;
   assign n_int_internal = (kbInPointer != kbReadPointer) && controlReg[7] == 1'b1 ? 1'b0 : (dispByteWritten == dispByteSent) && controlReg[6] == 1'b0 && controlReg[5] == 1'b1 ? 1'b0 : 1'b1;
   assign kbBuffCount = kbInPointer >= kbReadPointer ? 0 + kbInPointer - kbReadPointer : 8 + kbInPointer - kbReadPointer;
   assign n_rts = kbBuffCount > 4 ? 1'b1 : 1'b0;
   always @(negedge n_rd) begin
      // Standard CPU - present data on leading edge of rd
      if(regSel == 1'b1) begin
         dataOut <= {1'b0,kbBuffer[kbReadPointer]};
         if(kbInPointer != kbReadPointer) begin
            if(kbReadPointer < 7) begin
               kbReadPointer <= kbReadPointer + 1;
            end
            else begin
               kbReadPointer <= 0;
            end
         end
      end
      else begin
         dataOut <= statusReg;
      end
   end
   
   always @(posedge n_wr) begin
      // Standard CPU - capture data on trailing edge of wr
      if(regSel == 1'b1) begin
         if(dispByteWritten == dispByteSent) begin
            dispByteWritten <=  ~dispByteWritten;
            dispByteLatch <= dataIn;
         end
      end
      else begin
         controlReg <= dataIn;
      end
   end
   
   // PROCESS DATA FROM PS2 KEYBOARD


   // IceStorm cannot infer bidirectional I/Os
   
`ifdef use_sb_io
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   ps2_clk_buffer
     (
      .PACKAGE_PIN(ps2Clk),
      .OUTPUT_ENABLE(!ps2ClkOut),
      .D_OUT_0(1'b0),
      .D_IN_0(ps2ClkIn)
      );
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   ps2_data_buffer
     (
      .PACKAGE_PIN(ps2Data),
      .OUTPUT_ENABLE(!ps2DataOut),
      .D_OUT_0(1'b0),
      .D_IN_0(ps2DataIn)
      );
`else
   assign ps2Clk = ps2ClkOut == 1'b0 ? ps2ClkOut : 1'bZ;
   assign ps2ClkIn = ps2Clk;   
   assign ps2Data = ps2DataOut == 1'b0 ? ps2DataOut : 1'bZ;
   assign ps2DataIn = ps2Data;   
`endif
   
   // PS2 clock de-glitcher - important because the FPGA is very sensistive
   // Filtered clock will not switch low to high until there is 50 more high samples than lows
   // hysteresis will then not switch high to low until there is 50 more low samples than highs.
   // Introduces a minor (1uS) delay with 50MHz clock
   always @(negedge clk) begin
      if(ps2ClkIn == 1'b1 && ps2ClkFilter == 50) begin
         ps2ClkFiltered <= 1'b1;
      end
      if(ps2ClkIn == 1'b1 && ps2ClkFilter != 50) begin
         ps2ClkFilter <= ps2ClkFilter + 1;
      end
      if(ps2ClkIn == 1'b0 && ps2ClkFilter == 0) begin
         ps2ClkFiltered <= 1'b0;
      end
      if(ps2ClkIn == 1'b0 && ps2ClkFilter != 0) begin
         ps2ClkFilter <= ps2ClkFilter - 1;
      end
   end
   
   always @(negedge clk) begin : P1
      // 11 bits
      // start(0) b0 b1 b2 b3 b4 b5 b6 b7 parity(odd) stop(1)
      
      ps2PrevClk <= ps2ClkFiltered;
      if(n_kbWR == 1'b0 && kbWriteTimer < 25000) begin
         ps2WriteClkCount <= 0;
         kbWRParity <= 1'b1;
         kbWriteTimer <= kbWriteTimer + 1;
         // wait
      end
      else if(n_kbWR == 1'b0 && kbWriteTimer < 50000) begin
         ps2ClkOut <= 1'b0;
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b0 && kbWriteTimer < 75000) begin
         ps2DataOut <= 1'b0;
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b0 && kbWriteTimer == 75000) begin
         ps2ClkOut <= 1'b1;
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b0 && kbWriteTimer < 76000) begin
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b1 && ps2PrevClk == 1'b1 && ps2ClkFiltered == 1'b0) begin
         // start of high-to-low cleaned ps2 clock
         kbWatchdogTimer <= 0;
         if(ps2ClkCount == 0) begin
            // start
            ps2Byte <= {8{1'b0}};
            ps2ClkCount <= ps2ClkCount + 1;
         end
         else if(ps2ClkCount < 9) begin
            // data
            ps2Byte <= {ps2DataIn,ps2Byte[7:1]};
            ps2ClkCount <= ps2ClkCount + 1;
         end
         else if(ps2ClkCount == 9) begin
            // parity - use this time to decode
            if((ps2Byte < 132)) begin
               if(ps2Shift == 1'b0) begin
                  ps2ConvertedByte <= kbUnshifted[ps2Byte];
               end
               else begin
                  ps2ConvertedByte <= kbShifted[ps2Byte];
               end
            end
            else begin
               ps2ConvertedByte <= {7{1'b0}};
            end
            ps2ClkCount <= ps2ClkCount + 1;
         end
         else begin
            // stop bit - use this time to store
            // F-keys
            if(ps2ConvertedByte > 8'h 10 && ps2ConvertedByte < 8'h 1D) begin
               if(ps2PreviousByte != 8'h F0) begin
                  FNtoggledKeysSig[ps2ConvertedByte - 16] <= FNtoggledKeysSig[ps2ConvertedByte - 16];
                  FNkeysSig[ps2ConvertedByte - 16] <= 1'b1;
               end
               else begin
                  FNkeysSig[ps2ConvertedByte - 16] <= 1'b0;
               end
               // SHIFT
            end
            else if(ps2Byte == 8'h 12 || ps2Byte == 8'h 59) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Shift <= 1'b1;
               end
               else begin
                  ps2Shift <= 1'b0;
               end
               // CTRL
            end
            else if(ps2Byte == 8'h 14) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Ctrl <= 1'b1;
               end
               else begin
                  ps2Ctrl <= 1'b0;
               end
               // SCROLL, CAPS AND NUM
            end
            else if(ps2Byte == 8'h AA) begin
               ps2WriteByte <= 8'h ED;
               ps2WriteByte2[0] <= ps2Scroll;
               ps2WriteByte2[1] <= ps2Num;
               ps2WriteByte2[2] <= ps2Caps;
               ps2WriteByte2[7:3] <= 5'b00000;
               n_kbWR <= 1'b0;
               kbWriteTimer <= 0;
            end
            else if(ps2Byte == 8'h 7E) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Scroll <=  ~ps2Scroll;
                  ps2WriteByte <= 8'h ED;
                  ps2WriteByte2[0] <=  ~ps2Scroll;
                  ps2WriteByte2[1] <= ps2Num;
                  ps2WriteByte2[2] <= ps2Caps;
                  ps2WriteByte2[7:3] <= 5'b00000;
                  n_kbWR <= 1'b0;
                  kbWriteTimer <= 0;
               end
            end
            else if(ps2Byte == 8'h 77) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Num <=  ~ps2Num;
                  ps2WriteByte <= 8'h ED;
                  ps2WriteByte2[0] <= ps2Scroll;
                  ps2WriteByte2[1] <=  ~ps2Num;
                  ps2WriteByte2[2] <= ps2Caps;
                  ps2WriteByte2[7:3] <= 5'b00000;
                  n_kbWR <= 1'b0;
                  kbWriteTimer <= 0;
               end
            end
            else if(ps2Byte == 8'h 58) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Caps <=  ~ps2Caps;
                  ps2WriteByte <= 8'h ED;
                  ps2WriteByte2[0] <= ps2Scroll;
                  ps2WriteByte2[1] <= ps2Num;
                  ps2WriteByte2[2] <=  ~ps2Caps;
                  ps2WriteByte2[7:3] <= 5'b00000;
                  n_kbWR <= 1'b0;
                  kbWriteTimer <= 0;
               end
               // ACK
            end
            else if(ps2Byte == 8'h FA) begin
               if(ps2WriteByte != 8'h FF) begin
                  n_kbWR <= 1'b0;
                  kbWriteTimer <= 0;
               end
               // ASCII CHARACTER
            end
            else if((ps2PreviousByte != 8'h F0) && (ps2ConvertedByte != 8'h 00)) begin
               if(ps2PreviousByte == 8'h E0 && ps2Byte == 8'h 71) begin
                  // DELETE
                  kbBuffer[kbInPointer] <= 7'b1111111;
                  // 7F
               end
               else if(ps2Ctrl == 1'b1) begin
                  kbBuffer[kbInPointer] <= {2'b00,ps2ConvertedByte[4:0]};
               end
               else if(ps2ConvertedByte > 8'h 40 && ps2ConvertedByte < 8'h 5B && ps2Caps == 1'b1) begin
                  kbBuffer[kbInPointer] <= ps2ConvertedByte | 7'b0100000;
               end
               else if(ps2ConvertedByte > 8'h 60 && ps2ConvertedByte < 8'h 7B && ps2Caps == 1'b1) begin
                  kbBuffer[kbInPointer] <= ps2ConvertedByte & 7'b1011111;
               end
               else begin
                  kbBuffer[kbInPointer] <= ps2ConvertedByte;
               end
               if(kbInPointer < 7) begin
                  kbInPointer <= kbInPointer + 1;
               end
               else begin
                  kbInPointer <= 0;
               end
            end
            ps2PreviousByte <= ps2Byte;
            ps2ClkCount <= 0;
         end
         // write to keyboard
      end
      else if(n_kbWR == 1'b0 && ps2PrevClk == 1'b1 && ps2ClkFiltered == 1'b0) begin
         // start of high-to-low cleaned ps2 clock
         kbWatchdogTimer <= 0;
         if(ps2WriteClkCount < 8) begin
            if((ps2WriteByte[ps2WriteClkCount] == 1'b1)) begin
               ps2DataOut <= 1'b1;
               kbWRParity <=  ~kbWRParity;
            end
            else begin
               ps2DataOut <= 1'b0;
            end
            ps2WriteClkCount <= ps2WriteClkCount + 1;
         end
         else if(ps2WriteClkCount == 8) begin
            ps2DataOut <= kbWRParity;
            ps2WriteClkCount <= ps2WriteClkCount + 1;
         end
         else if(ps2WriteClkCount == 9) begin
            ps2WriteClkCount <= ps2WriteClkCount + 1;
            ps2DataOut <= 1'b1;
         end
         else if(ps2WriteClkCount == 10) begin
            ps2WriteByte <= ps2WriteByte2;
            ps2WriteByte2 <= 8'h FF;
            n_kbWR <= 1'b1;
            ps2WriteClkCount <= 0;
            ps2DataOut <= 1'b1;
         end
      end
      else begin
         // COMMUNICATION ERROR
         // if no edge then increment the timer
         // if a large time has elapsed since the last pulse was read then
         // re-sync the keyboard
         if(kbWatchdogTimer > 30000000) begin
            kbWatchdogTimer <= 0;
            ps2ClkCount <= 0;
            if(n_kbWR == 1'b0) begin
               ps2WriteByte <= 8'h ED;
               ps2WriteByte2[0] <= ps2Scroll;
               ps2WriteByte2[1] <= ps2Num;
               ps2WriteByte2[2] <= ps2Caps;
               ps2WriteByte2[7:3] <= 5'b00000;
               kbWriteTimer <= 0;
            end
         end
         else begin
            kbWatchdogTimer <= kbWatchdogTimer + 1;
         end
      end
   end
   
   // PROCESS DATA WRITTEN TO DISPLAY
   always @(negedge clk or negedge n_reset) begin
      if(n_reset == 1'b0) begin
         dispAttWRData <= DEFAULT_ATT;
      end else begin
         case(dispState)
           idle : begin
              if((nextState != processingAdditionalParams) && (dispByteWritten != dispByteSent)) begin
                 dispCharWRData <= dispByteLatch;
                 dispByteSent <=  ~dispByteSent;
              end
              if((dispByteWritten != dispByteSent) || (nextState == processingAdditionalParams)) begin
                 if(dispByteLatch == 8'h 07) begin
                    // BEEP
                    // do nothing - ignore
                 end
                 else if(dispByteLatch == 8'h 1B) begin
                    // ESC
                    paramCount <= 0;
                    param1 <= 0;
                    param2 <= 0;
                    param3 <= 0;
                    param4 <= 0;
                    nextState <= waitForLeftBracket;
                 end
                 else if(nextState == waitForLeftBracket && dispByteLatch == 8'h 5B) begin
                    // ESC[
                    nextState <= processingParams;
                    paramCount <= 1;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 48 && param1 == 0) begin
                    // ESC[H
                    cursorVert <= 0;
                    cursorHoriz <= 0;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 4B && param1 == 0) begin
                    // ESC[K - erase EOL
                    dispState <= clearLine;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 73 && param1 == 0) begin
                    // ESC[s - save cursor pos
                    savedCursorHoriz <= cursorHoriz;
                    savedCursorVert <= cursorVert;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 75 && param1 == 0) begin
                    // ESC[u - restore cursor pos
                    cursorHoriz <= savedCursorHoriz;
                    cursorVert <= savedCursorVert;
                    paramCount <= 0;
                 end
                 else if(paramCount > 0 && dispByteLatch == 8'h 3B) begin
                    // ESC[{param1};{param2}...
                    paramCount <= paramCount + 1;
                 end
                 else if(paramCount > 0 && dispByteLatch > 8'h 2F && dispByteLatch < 8'h 3A) begin
                    // numeric
                    if(paramCount == 1) begin
                       // ESC[{param1}
                       param1 <= param1 * 10 + ((dispByteLatch - 48));
                    end
                    else if(paramCount == 2) begin
                       // ESC[{param1};{param2}
                       param2 <= param2 * 10 + ((dispByteLatch - 48));
                    end
                    else if(paramCount == 3) begin
                       // ESC[{param1};{param2};{param3}
                       param3 <= param3 * 10 + ((dispByteLatch - 48));
                    end
                    else if(paramCount == 4) begin
                       // ESC[{param1};{param2};{param3};{param4}
                       param4 <= param4 * 10 + ((dispByteLatch - 48));
                    end
                 end
                 else if(paramCount == 1 && param1 == 2 && dispByteLatch == 8'h 4A) begin
                    // ESC[2J - clear screen
                    cursorVert <= 0;
                    cursorHoriz <= 0;
                    cursorVertRestore <= 0;
                    cursorHorizRestore <= 0;
                    dispState <= clearScreen;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && param1 == 0 && dispByteLatch == 8'h 4A) begin
                    // ESC[0J or ESC[J - clear from cursor to end of screen
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    dispState <= clearScreen;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 4C) begin
                    // ESC[L - insert line
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    cursorHoriz <= HORIZ_CHAR_MAX;
                    cursorVert <= VERT_CHAR_MAX - 1;
                    dispState <= insertLine;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 4D) begin
                    // ESC[M - delete line
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    cursorHoriz <= 0;
                    cursorVert <= cursorVert + 1;
                    dispState <= deleteLine;
                    paramCount <= 0;
                 end
                 else if(paramCount > 0 && dispByteLatch == 8'h 6D) begin
                    // ESC[{param1}m or ESC[{param1};{param2}m- set graphics rendition
                    if(param1 == 0) begin
                       attInverse <= 1'b0;
                       attBold <= ANSI_DEFAULT_ATT[3];
                       dispAttWRData <= ANSI_DEFAULT_ATT;
                    end
                    if(param1 == 1) begin
                       attBold <= 1'b1;
                       //                    if attInverse='0' then
                       dispAttWRData[3] <= 1'b1;
                       //                    else
                       //                       dispAttWRData(7) <= '1';
                       //                    end if;
                    end
                    if(param1 == 22) begin
                       attBold <= 1'b0;
                       //                    if attInverse='0' then
                       dispAttWRData[3] <= 1'b0;
                       //                    else
                       //                       dispAttWRData(7) <= '0';
                       //                    end if;
                    end
                    if(param1 == 7) begin
                       if(attInverse == 1'b0) begin
                          attInverse <= 1'b1;
                          dispAttWRData[7:4] <= dispAttWRData[3:0];
                          dispAttWRData[3:0] <= dispAttWRData[7:4];
                       end
                    end
                    if(param1 == 27) begin
                       if(attInverse == 1'b1) begin
                          attInverse <= 1'b0;
                          dispAttWRData[7:4] <= dispAttWRData[3:0];
                          dispAttWRData[3:0] <= dispAttWRData[7:4];
                       end
                    end
                    if(param1 > 29 && param1 < 38) begin
                       if(attInverse == 1'b0) begin
                          dispAttWRData[2:0] <= ((param1 - 30));
                          dispAttWRData[3] <= attBold;
                       end
                       else begin
                          dispAttWRData[6:4] <= ((param1 - 30));
                          dispAttWRData[7] <= attBold;
                       end
                    end
                    if(param1 > 39 && param1 < 48) begin
                       if(attInverse == 1'b0) begin
                          dispAttWRData[6:4] <= ((param1 - 40));
                          dispAttWRData[7] <= attBold;
                       end
                       else begin
                          dispAttWRData[2:0] <= ((param1 - 40));
                          dispAttWRData[3] <= attBold;
                       end
                    end
                    if(param1 > 89 && param1 < 98) begin
                       if(attInverse == 1'b0) begin
                          dispAttWRData[2:0] <= ((param1 - 90));
                          dispAttWRData[3] <= 1'b1;
                       end
                       else begin
                          dispAttWRData[6:4] <= ((param1 - 90));
                          dispAttWRData[7] <= 1'b1;
                       end
                    end
                    if(param1 > 99 && param1 < 108) begin
                       if(attInverse == 1'b0) begin
                          dispAttWRData[6:4] <= ((param1 - 100));
                          dispAttWRData[7] <= 1'b1;
                       end
                       else begin
                          dispAttWRData[2:0] <= ((param1 - 100));
                          dispAttWRData[3] <= 1'b1;
                       end
                    end
                    // allow for second parameter - must process individually and in sequence
                    if(paramCount > 1) begin
                       param1 <= param2;
                       param2 <= param3;
                       param3 <= param4;
                       paramCount <= paramCount - 1;
                       nextState <= processingAdditionalParams;
                    end
                    else begin
                       paramCount <= 0;
                       nextState <= none;
                    end
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 41) begin
                    // ESC[{param1}A - Cursor up
                    if(param1 == 0 && cursorVert > 0) begin
                       // no param to default to 1
                       cursorVert <= cursorVert - 1;
                    end
                    else if(param1 < cursorVert) begin
                       cursorVert <= cursorVert - param1;
                    end
                    else begin
                       cursorVert <= 0;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 42) begin
                    // ESC[{param1}B - Cursor down
                    if(param1 == 0 && cursorVert < VERT_CHAR_MAX) begin
                       // no param to default to 1
                       cursorVert <= cursorVert + 1;
                    end
                    else if(((cursorVert + param1)) < VERT_CHAR_MAX) begin
                       cursorVert <= cursorVert + param1;
                    end
                    else begin
                       cursorVert <= VERT_CHAR_MAX;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 43) begin
                    // ESC[{param1}C - Cursor forward
                    if(param1 == 0 && cursorHoriz < HORIZ_CHAR_MAX) begin
                       // no param to default to 1
                       cursorHoriz <= cursorHoriz + 1;
                    end
                    else if(((cursorHoriz + param1)) < HORIZ_CHAR_MAX) begin
                       cursorHoriz <= cursorHoriz + param1;
                    end
                    else begin
                       cursorHoriz <= HORIZ_CHAR_MAX;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 44) begin
                    // ESC[{param1}D - Cursor backward
                    if(param1 == 0 && cursorHoriz > 0) begin
                       // no param to default to 1
                       cursorHoriz <= cursorHoriz - 1;
                    end
                    else if(param1 < cursorHoriz) begin
                       cursorHoriz <= cursorHoriz - param1;
                    end
                    else begin
                       cursorHoriz <= 0;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 2 && dispByteLatch == 8'h 48) begin
                    // ESC[{param1};{param2}H
                    if(param1 < 1) begin
                       cursorVert <= 0;
                    end
                    else if(param1 > VERT_CHARS) begin
                       cursorVert <= VERT_CHARS - 1;
                    end
                    else begin
                       cursorVert <= param1 - 1;
                    end
                    if(param2 < 0) begin
                       cursorHoriz <= 0;
                    end
                    else if(param2 > HORIZ_CHARS) begin
                       cursorHoriz <= HORIZ_CHARS - 1;
                    end
                    else begin
                       cursorHoriz <= param2 - 1;
                    end
                    paramCount <= 0;
                 end
                 else begin
                    dispState <= dispWrite;
                    nextState <= none;
                    paramCount <= 0;
                 end
              end
           end
           dispWrite : begin
              if(dispCharWRData == 13) begin
                 cursorHoriz <= 0;
                 dispState <= idle;
              end
              else if(dispCharWRData == 10) begin
                 if(cursorVert < VERT_CHAR_MAX) begin
                    cursorVert <= cursorVert + 1;
                    dispState <= idle;
                 end
                 else begin
                    if(startAddr < ((CHARS_PER_SCREEN - HORIZ_CHARS))) begin
                       startAddr <= startAddr + HORIZ_CHARS;
                    end
                    else begin
                       startAddr <= 0;
                    end
                    cursorHorizRestore <= cursorHoriz;
                    cursorVertRestore <= cursorVert;
                    dispState <= clearLine;
                 end
              end
              else if(dispCharWRData == 12) begin
                 cursorVert <= 0;
                 cursorHoriz <= 0;
                 cursorHorizRestore <= 0;
                 cursorVertRestore <= 0;
                 dispState <= clearScreen;
              end
              else if(dispCharWRData == 8 || dispCharWRData == 127) begin
                 if(cursorHoriz > 0) begin
                    cursorHoriz <= cursorHoriz - 1;
                 end
                 else if(cursorHoriz == 0 && cursorVert > 0) begin
                    cursorHoriz <= HORIZ_CHAR_MAX;
                    cursorVert <= cursorVert - 1;
                 end
                 dispState <= clearChar;
              end
              else begin
                 dispWR <= 1'b1;
                 dispState <= dispNextLoc;
              end
           end
           dispNextLoc : begin
              dispWR <= 1'b0;
              if((cursorHoriz < HORIZ_CHAR_MAX)) begin
                 cursorHoriz <= cursorHoriz + 1;
                 dispState <= idle;
              end
              else begin
                 cursorHoriz <= 0;
                 if(cursorVert < VERT_CHAR_MAX) begin
                    cursorVert <= cursorVert + 1;
                    dispState <= idle;
                 end
                 else begin
                    if(startAddr < ((CHARS_PER_SCREEN - HORIZ_CHARS))) begin
                       startAddr <= startAddr + HORIZ_CHARS;
                    end
                    else begin
                       startAddr <= 0;
                    end
                    cursorHorizRestore <= 0;
                    cursorVertRestore <= cursorVert;
                    dispState <= clearLine;
                 end
              end
           end
           clearLine : begin
              dispCharWRData <= 8'h 20;
              dispWR <= 1'b1;
              dispState <= clearL2;
           end
           clearL2 : begin
              dispWR <= 1'b0;
              if((cursorHoriz < HORIZ_CHAR_MAX)) begin
                 cursorHoriz <= cursorHoriz + 1;
                 dispState <= clearLine;
              end
              else begin
                 cursorHoriz <= cursorHorizRestore;
                 cursorVert <= cursorVertRestore;
                 dispState <= idle;
              end
           end
           clearChar : begin
              dispCharWRData <= 8'h 20;
              dispWR <= 1'b1;
              dispState <= clearC2;
           end
           clearC2 : begin
              dispWR <= 1'b0;
              dispState <= idle;
           end
           clearScreen : begin
              dispCharWRData <= 8'h 20;
              dispWR <= 1'b1;
              dispState <= clearS2;
           end
           clearS2 : begin
              dispWR <= 1'b0;
              if((cursorHoriz < HORIZ_CHAR_MAX)) begin
                 cursorHoriz <= cursorHoriz + 1;
                 dispState <= clearScreen;
              end
              else begin
                 if((cursorVert < VERT_CHAR_MAX)) begin
                    cursorHoriz <= 0;
                    cursorVert <= cursorVert + 1;
                    dispState <= clearScreen;
                 end
                 else begin
                    cursorHoriz <= cursorHorizRestore;
                    cursorVert <= cursorVertRestore;
                    dispState <= idle;
                 end
              end
           end
           insertLine : begin
              dispCharWRData <= dispCharRDData;
              dispAttWRData <= dispAttRDData;
              cursorVert <= cursorVert + 1;
              dispState <= ins2;
           end
           ins2 : begin
              dispWR <= 1'b1;
              dispState <= ins3;
           end
           ins3 : begin
              dispWR <= 1'b0;
              if(cursorHoriz == 0 && cursorVert == (cursorVertRestore + 1)) begin
                 cursorVert <= cursorVertRestore;
                 dispState <= clearLine;
              end
              else if(cursorHoriz > 0) begin
                 cursorHoriz <= cursorHoriz - 1;
                 cursorVert <= cursorVert - 1;
                 dispState <= insertLine;
              end
              else begin
                 cursorHoriz <= HORIZ_CHAR_MAX;
                 cursorVert <= cursorVert - 2;
                 dispState <= insertLine;
              end
           end
           deleteLine : begin
              dispCharWRData <= dispCharRDData;
              dispAttWRData <= dispAttRDData;
              cursorVert <= cursorVert - 1;
              dispState <= del2;
           end
           del2 : begin
              dispWR <= 1'b1;
              dispState <= del3;
           end
           del3 : begin
              dispWR <= 1'b0;
              if(cursorHoriz == HORIZ_CHAR_MAX && cursorVert == (VERT_CHAR_MAX - 1)) begin
                 cursorHoriz <= 0;
                 cursorVert <= VERT_CHAR_MAX;
                 dispState <= clearLine;
              end
              else if(cursorHoriz < HORIZ_CHAR_MAX) begin
                 cursorHoriz <= cursorHoriz + 1;
                 cursorVert <= cursorVert + 1;
                 dispState <= deleteLine;
              end
              else begin
                 cursorHoriz <= 0;
                 cursorVert <= cursorVert + 2;
                 dispState <= deleteLine;
              end
           end
         endcase
      end
   end
   
   
endmodule
