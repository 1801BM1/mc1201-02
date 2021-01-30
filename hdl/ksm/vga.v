//************************************************************
//*   Текстовый видеоадаптер с VGA-выходом
//************************************************************
module vga (
// шина wishbone
   input                  wb_clk_i,   // тактовая частота шины
   input                  wb_rst_i,   // сброс
   input    [15:0]        wb_adr_i,   // адрес 
   input    [15:0]        wb_dat_i,   // входные данные
   output reg [15:0]      wb_dat_o,   // выходные данные
   input                  wb_cyc_i,   // начало цикла шины
   input                  wb_we_i,    // разрешение записи (0 - чтение)
   input                  wb_stb_i,   // строб цикла шины
   input    [1:0]         wb_sel_i,   // выбор конкретных байтов для записи - старший, младший или оба
   output reg             wb_ack_o,   // подтверждение выбора устройства
   // VGA      
   output reg             hsync,      // строчный синхросингал
   output reg             vsync,      // кадровый синхросигнал 
   output reg             vgar,       // видеовыход красный
   output reg             vgag,       // видеовыход зеленый
   output reg             vgab,       // видеовыход синий
   // управление     
   input [12:0]           cursor,     // адрес курсора
   input                  cursor_on,  // 0 - курсор невидим, 1 - отображается
   input                  cursor_type,// форма курсора, 0 - подчеркивание, 1 - блок
   input                  flash,      // импульсы переключения видимости мерцающих символов
   
// синхронизация с КГД
   output reg [10:0]      col,        // колонка X, 0-1055
   output reg [9:0]       row,        // строка Y, 0-627
   
   input clk50                        // тактовый сигнал 50 Мгц
);

   
wire pixel;  // выход данных шрифтовой памяти


// двухпортовый видеобуфер
reg[7:0] vram_even[1024:0];         // четные байты
reg[7:0] vram_odd[1024:0];          // нечетные байты
   
//************************************
//* ROM знакогенератора с шрифтами 
//************************************
fontrom fontrom0 (
      .address(font_adr), 
      .clock(clk50), 
      .q(pixel)
); 

//**********************************************
//* Стробы 
//**********************************************
wire bus_strobe = wb_cyc_i & wb_stb_i;         // строб цикла шины
wire bus_read_req = bus_strobe & ~wb_we_i;     // запрос чтения
wire bus_write_req = bus_strobe & wb_we_i;     // запрос записи
wire reset = wb_rst_i;

// формирователь ответа на цикл шины   
wire reply=wb_cyc_i & wb_stb_i & ~wb_ack_o;
   
// Сигнал ответа 
always @(posedge wb_clk_i or posedge wb_rst_i)
  if (wb_rst_i == 1'b1) wb_ack_o <= 1'b0;
  else wb_ack_o <= reply;

//**********************************************
// обработка шинных транзакций  
//**********************************************
always @(posedge wb_clk_i)  begin
   // Чтение данных из видеопамяти
   if (bus_read_req == 1'b1) begin
        wb_dat_o[7:0] <= vram_even[wb_adr_i[11:1]] ; 
        wb_dat_o[15:8] <= vram_odd[wb_adr_i[11:1]] ;
   end
   // запись данных в видеопамять   
   else if (bus_write_req == 1'b1)  begin
         // запись четных байтов 
         if (wb_sel_i[0] == 1'b1) vram_even[wb_adr_i[11:1]] <= wb_dat_i[7:0] ; 
         // запись нечетных байтов
         if (wb_sel_i[1] == 1'b1) vram_odd[wb_adr_i[11:1]] <= wb_dat_i[15:8] ; 
   end  
end 


//******************************************************
//* Видеоконтроллер   800*600
//******************************************************

reg[3:0]  fontcol;         // столбец шрифта
reg[4:0]  fontrow;         // строка шрифта
reg[12:0] char_adr;        // адрес текущего знакоместа в видеопамяти
reg[12:0] row_start_adr;   // адрес начала текущей строки в виедопамяти

reg[1:0]  cursor_match;    // флаг наличия курсора в текущей позиции

reg[7:0] char_evn;     // четный символ
reg[7:0] char_odd;     // нечетный символ
reg[14:0] font_adr;    // адрес в шрифтовой памяти
reg vout;              // регистр видеосигнала -состояние теущего пикселя (0 - откл, 1 - вкл)
reg vblank;            // регистр кадрового гашения видеосигнала   
reg [1:0] flashflag;   // признак вывода данного символа мерцающим   
reg cursor_field;      // произнак строки знакоместа, на которой отображается курсор

reg vram_a0;

//**********************************  
//* Процесс попиксельной обработки
//**********************************  
always @(posedge clk50) 
  if (reset == 1'b1) begin
    // сброс контроллера
    col <= 11'o0;
    row <= 10'o0;
    row_start_adr <= 13'o0; 
    fontrow <= 5'o0 ; 
  end
  else begin
  //**********************************  
  //*  счетчики разверток
  //**********************************  

  // конец полной видеостроки 
  if (col == 11'd1055) begin
    // переход на новую строку
    col <= 11'd0;
    // конец полного кадра
    if (row == 10'd627) begin
      // переход на новый кадр
      row <= 10'd0;
      row_start_adr <= 13'o0; 
      fontrow <= 5'o0 ; 
    end   
    else begin
      // кадр не завершен - смена строки
      row <= row + 1'b1;  
//      cursor_match[1] <= 1'b0;
      // счетчик строк шрифта
      if (row > 10'd22) begin  // видимая часть растра - со строки 23
         if (fontrow < 5'd23) fontrow <= fontrow + 1'b1; // счетчик строк шрифта - от 0 до 23
         else   begin
            row_start_adr <= row_start_adr + 7'd80; // сдвиг на 80 байт в адресе видеобуфера
            fontrow <= 5'o0; // заворачиваем счетчик колонок шрифта
         end   
      end     // счетчик строк шрифта
    end   // счетчик строк экрана
  end    
  else begin
   // строка не завершена - переход на новый пиксель
   col <= col + 1'b1;
  end
  
  //********************************
  //*    Строчная развертка
  //********************************
  
  // Формат строки: 
  //   0            40          840          928    1055 
  //   <back porch> <videoline> <front proch> <hsync>
  
  // левое и правое черное поле - гашение видеосигнала (horizontal porch)
  if ((col < 11'd39) || (col > 11'd838)) begin
      vout <= 1'b0;    // видеосигнал отключен
      fontcol <= 4'd8; // сброс счетчика колонок шрифта - начинаем с последней колонки 8 с учетом предвыборки
      char_adr <= row_start_adr; // адрес байта в видеобуфере -с первого байта текущей строки
      cursor_match[0] <= 1'b0;
  end   
  // видимая часть строки
  else begin
      //***************************************************
      //*  формирователь видеосигнала 
      //***************************************************
         // счетчик колонок знакоместа - от 0 до 9
         if (fontcol < 4'd9) fontcol <= fontcol + 1'b1;
         else fontcol <= 4'd0;
         // формирование адреса текущей точки в массиве шрифтов
         if (vram_a0 == 1'b0)  font_adr <= {fontrow[3:0], fontcol[2:0], char_evn} ; // четные символы
         else                  font_adr <= {fontrow[3:0], fontcol[2:0], char_odd} ; // нечетные символы
         //***************************************************
         // запись регистра видеовыхода
         //***************************************************
         // межсимвольные промежутки - позиции 0 и 1
         if (fontcol[3:1] == 3'd0) vout <= 1'b0;
         // 12 строк знакоместа
         else if (fontrow < 4'd12) begin
                  // пиксели,занимаемые курсором, имеют инверсию видеосигнала
                  if ((fontcol<4'd9) && (|cursor_match) && cursor_field) vout <= ~pixel; 
                  // формирование обычных пикселей с учетом флага мерцания
                  else   vout <= pixel & (flash | flashflag[1]) ; 
         end  
         // межстрочные промежутки, начиная со строки 12 знакоместа
         else begin
            vout <= 1'b0;  
         end   
         //********************************************
         //*  Формирователь флага мерцания символов
         //********************************************
         // Флаг формируется для символов с кодами 00-1F      
         if ((vram_a0 == 1'b0) && (char_evn[7:5] == 3'b000) ||  // для четных символов
             (vram_a0 == 1'b1) && (char_odd[7:5] == 3'b000))    // для нечетных символов
               flashflag[0] <= 1'b0;  // флаг поднят (0)
         else  flashflag[0] <= 1'b1;  // для остальных флаг опущен (1)
         flashflag[1] <= flashflag[0]; // задержка флага на 1 пиксель

         // переход на новый символ - предвыборка байта из видеобуфера
         if (fontcol == 4'd8) begin
            //***************************************************
            // выборка четного и нечетного байта из видеопамяти
            //***************************************************
            char_evn <= vram_even[char_adr[12:1]] ; // четный теущий символ
            char_odd <= vram_odd[char_adr[12:1]] ; // нечетный текущий символ
            vram_a0 <= char_adr[0];  // селектор четного-нечетного байта
            char_adr <= char_adr + 1'b1; // переход на новый символ
            fontcol <= fontcol + 1'b1;   // переход на следующую колонку знакоместа
            //********************************
            // обработка курсора
            //********************************
            if (((char_adr) == cursor) & cursor_on)  cursor_match[0] <= 1'b1;  // признак курсора в данном знакоместе
            else                                     cursor_match[0] <= 1'b0; //{cursor_match[2:0], 1'b0} ; // курсора нет - начинаем заполнять регистр нулями
            // строки знакоместа, содержащие курсор:
            cursor_field <= (fontrow[3:1] == 3'b101)  // подчеркивание - строки 10-11 
                            | cursor_type;         // блок - все знакоместо
         end   
         
         // Селектор цветов выводимого видеосигнала
         vgab <= ((char_adr> 13'd70) && (char_adr < 13'd80) && vblank)  ? vout:1'b0;   // синий - только часы
         vgar <= (((row_start_adr == 13'b0) || ((|cursor_match) && cursor_field)) && vblank)? vout:1'b0;  // красный - служебная строка и курсор 
         vgag <= ((row_start_adr > 13'd79) && vblank) ? vout:1'b0;                     // зеленый - все строки начиная с 1
  end
  //******************************************
  // расширение курсора на полное знакоместо
  //******************************************
  cursor_match[1] <= cursor_match[0];
  //***************************************
  //*  Строчная синхронизация
  //***************************************
//  if (col > 11'd927) hsync <= 1'b1;
//  else hsync <= 1'b0;
  if ((col > 11'd900) && (col < 11'd1028)) hsync <= 1'b1;
  else hsync <= 1'b0;

  //*********************************
  //*  Кадровая развертка
  //*********************************
  
  // Формат кадра
  // 0            23           623           624    627
  // <back porch> <videoframe> <front proch> <vsync>
  //
  // Пиксельный формат:12 пикселей видео + 12 пикселей разрыв. 24 пикселя на строку текста, всего 25 строк на экран.
  //  
  
  // верхнее и нижнее черное поле -front и back porch
  if ((row < 10'd23) || (row > 10'd622)) vblank <= 1'b0;  
  else vblank <= 1'b1;

  //**************************************  
  // кадровая синхронизация
  //**************************************  
  if (row > 10'd624) vsync <= 1'b1;
  else vsync <= 1'b0;
end  

endmodule
