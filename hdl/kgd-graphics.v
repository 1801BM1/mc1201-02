//
// Графический контроллер КГД
//
module kgd (

// шина wishbone
   input			         wb_clk_i,	// тактовая частота шины
	input			         wb_rst_i,	// сброс
	input	 [2:0]           wb_adr_i,	// адрес 
	input	 [15:0]          wb_dat_i,	// входные данные
   output reg [15:0]	     wb_dat_o,	// выходные данные
	input					 wb_cyc_i,	// начало цикла шины
	input					 wb_we_i,		// разрешение записи (0 - чтение)
	input					 wb_stb_i,	// строб цикла шины
	input	 [1:0]           wb_sel_i,   // выбор конкретных байтов для записи - старший, младший или оба
	output reg			     wb_ack_o,	// подтверждение выбоора устройства

   input clk50,                // тактовый сигнал 50 Мгц
	
// VGA      
   output reg hsync,        // строчный синхросингал
   output reg vsync,        // кадровый синхросигнал 
   output vgavideo,             // видеовыход 
// Управление
	output genable		// переключение дисплея на графический контроллер
);


// регистры управления
reg g_on;    // разрешение графики
reg t_off;	 // запрет текста
assign genable=g_on;

// регистр адреса
reg [13:0] areg;
reg vbuf_write;

// регистр текущего пикселя
reg vout;
reg vblank;
assign vgavideo = vout & vblank;
wire [7:0] vbufdata;

// Сигналы упраления обменом с шиной
wire bus_strobe = wb_cyc_i & wb_stb_i;         // строб цикла шины
wire bus_read_req = bus_strobe & ~wb_we_i;     // запрос чтения
wire bus_write_req = bus_strobe & wb_we_i;     // запрос записи
wire reset=wb_rst_i;

//********************************************
//*   Модуль двухпортовой видеопамяти
//********************************************
kgdvram vbuf(
	.address_a(areg),
	.address_b(yadr+col[10:1]-11'd20),
	.clock(wb_clk_i),
	.data_a(wb_dat_i[7:0]),
	.wren_a(vbuf_write),
	.wren_b(1'b0),
	.q_a(vbufdata),
	.q_b(videobit)
);	

//**************************************
//*  Сигнал ответа 
//**************************************
// формирователь ответа на цикл шины	
wire reply=wb_cyc_i & wb_stb_i & ~wb_ack_o;
reg reply0;

always @(posedge wb_clk_i or posedge wb_rst_i)
    if (wb_rst_i == 1'b1) begin 
		wb_ack_o <= 1'b0;
		reply0 <= 1'b0;
	 end	
	 // задержка ответа на 1 такт, чтобы модуль altsyncram успел записать данные
    else begin
	   reply0 <= reply;
	   wb_ack_o <= reply0;
    end

//*******************************************
//* Обработка шинных транзакций
//******************************************	
always @(posedge wb_clk_i) 
	if (reset == 1'b1) begin
		g_on <= 1'b0;
		t_off <= 1'b0;
		areg <= 14'o0;
		vbuf_write <= 1'b0;
	end
	else begin
   // обработка запросов с шины
      // чтение регистров
      if (bus_read_req == 1'b1)   
         case (wb_adr_i[2:1])
			   // 176640 - регистр управления   
            2'b00:   wb_dat_o <= {g_on, t_off, 14'b0};   
								
				// 176640 - регистр данных
				2'b01:  	wb_dat_o <= {8'o0,vbufdata};
					
				// 176644 - регистр адреса				
            2'b10:   wb_dat_o <= {2'b0, areg};
								
				// 176646 - регистр счетчика
				2'b11:	wb_dat_o <= yadr[16:3]+col[10:4];
			endcase			
	
      // запись регистров	
      else if (bus_write_req == 1'b1)  
         case (wb_adr_i[2:1])
			   // 176640 - регистр управления   
            2'b00:  if (wb_sel_i[1] == 1'b1) begin
								g_on <= wb_dat_i[15];
								t_off <= wb_dat_i[14];
						  end	
						  
				// 176640 - регистр данных
				2'b01:   if (wb_sel_i[0] == 1'b1) 
				   if (reply0 == 1'b0) vbuf_write <=1'b1;
					else vbuf_write <= 1'b0;
							
				// 176644 - регистр адреса				
            2'b10:  	begin
					if (wb_sel_i[0] == 1'b1) areg[7:0] <= wb_dat_i[7:0];
					if (wb_sel_i[1] == 1'b1) areg[13:8] <= wb_dat_i[13:8];
				 end	  
		   endcase
	end
	
//******************************************************
//* Видеоконтроллер	
//******************************************************
// Оба синхроимпульса имеют положительную полярность
// 
// Размер графического экрана - 400*286, в удвоенном режиме - 800*572. Первые 28 строк пусты.
//   50 байтов на строку

reg [10:0] col;  // колонка X, 0-1055
reg [9:0]  row;  // строка Y, 0-627

wire videobit;
reg [16:0] yadr; // адрес первого бита текущей строки в видеопамяти

//**********************************  
//* Процесс попиксельной обработки
//**********************************  
always @(posedge clk50) 
  if (reset == 1'b1) begin
    // сброс контроллера
    col <= 11'o0;
	 row <= 10'o0;
	 vout <= 1'b0;
	 hsync <= 1'b0;
	 vsync <= 1'b0;
	 yadr <= 17'd0;
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
		yadr <= 17'd0;  // сбрасываем счетчик адреса начала строки
	 end	
    else begin
	   // кадр не завершен - смена строки
		row <= row + 1'b1;  
		// смена стартового адреса строки через строку, начиная со строки 51
		if ((row > 10'd50) && (row[0] == 0)) yadr <= yadr+14'd400;
	 end	
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
  
  // левое и правое черное поле - гашение видеосигнала (horizontal back porch)
  if ((col < 11'd40) || (col > 11'd839)) vout <= 1'b0;
  // видимая часть строки
  else begin
		vout <= videobit;  // выводим теущий бит из видеопамяти на экран
  end	
  
  // Строчный синхроиспульс
  if (col > 11'd927) hsync <= 1'b1;
  else hsync <= 1'b0;

  //*********************************
  //*  Кадровая развертка
  //*********************************
  
  // Формат кадра
  // 0            23           623           624    627
  // <back porch> <videoframe> <front proch> <vsync>
  
  // верхнее и нижнее черное поле -front и back porch
  //  51 - это 23 (само черное поле) + 28 (неиспользуемые графические строки)
  if ((row < 10'd51) || (row > 10'd622)) vblank <= 1'b0;  
  else vblank <= 1'b1;
  
  // кадровый синхроимпульс
  if (row > 10'd624) vsync <= 1'b1;
  else vsync <= 1'b0;
end  

endmodule	
		
