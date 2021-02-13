//
//  Процессорный модуль - плата МС1201.01 (ДВК-1)
//
//  Центральный процессор - 1801ВМ1
//  Теневое ПЗУ - 000
// 
// ======================================================================================

// Содержимое регистра начального пуска. 
//
//  00 - пуск через вектор 24
//  01 - выход в пульт
//  10 - загрузка с DX
//  11 - пуск с 140000
//
// Из всего вышеперечисленного реально работают только выход а пульт и автозагрузка с диска. Все остальное лезет 
// в регистр перфоратора 177556 , и вываливается в пульт по ошибке шины.
//
`define STARTUP 2'b01
//
// Начальное состояние таймера: 0 - выключен, 1 - включен
`define timer_init 1'b1


module mc1201_01 (
// Синхросигналы  
   input  clk50,               // входная тактовая частота платы - 50 МГц
   output busclk,              // Основной синхросигнал общей шины
   output sdclk,               // Синхросигнал SD-карты
	output clkrdy,              // сигнал готовности тактового генератора
   input  cpuslow,             // Режим замедления процессора

// Шина Wishbone                                       
   input  cpu_gnt_i,           // 1 - разрешение cpu работать с шиной
                               // 0 - DMA с внешними устройствами, cpu отключен от шины и бесконечно ждет ответа REPLY (ack)
   output [15:0] cpu_adr_o,    // выход шины адреса
   output [15:0] cpu_dat_o,    // выход шины данных
   input  [15:0] cpu_dat_i,    // вход шины данных
   output cpu_cyc_o,           // Строб цила wishbone
   output cpu_we_o,            // разрешение записи
   output [1:0] cpu_sel_o,     // выбор байтов для передачи
   output cpu_stb_o,           // строб данных

   output sysram_stb,          // строб обращения к системной памяти
   input  global_ack,          // подтверждение обмена от памяти и устройств страницы ввода-вывода
   
// Сбросы и прерывания
   output vm_init,             // Выход сброса для периферии
   input  dclo,                // Вход сброса процессора
   input  aclo,                // Сигнал аварии питания
   input  halt,                // Прерывание входа в пультовоый режим
   input  virq,                // Векторное прерывание

// Шины обработки прерываний                                       
   input  [15:0] ivec,         // Шина приема вектора прерывания
   output istb,                // Строб приема вектора прерывания
   input  iack,                // Подтверждение приема вектора прерывания

// Таймер
	input  timer_50,            // Сигнал таймерного прерывания 50 Гц
	input  timer_button,        // кнопка включения-отключения таймера
	output reg timer_status     // линия индикатора состояния таймера
);

// Регистр начального пуска
reg [15:0] startup_reg;
// регистры sel2 - четный и нечетный
reg  [15:0]	SEL2_even, SEL2_odd;				

// Синхросигналы
wire clk_p;    
wire clk_n;

// Локальная шина процессора
wire [15:0] local_dat_i;    // локальная входная шина данных
wire local_cyc;             // локальный сигнал начала транзацкии
wire cpu_ack;               // вход REPLY процессора
wire [3:1]	vm_irq;			 // собственные входы запросов прерывания
wire cpu_dev_stb;           // запрос на доступ к периферийному блоку процессора 
wire cpu_dev_ack;           // ответ от периферийного блока
wire [15:0]	cpu_dev_dat;    // шина данных периферийного блока
wire [2:1]	vm_sel;			 // выбор SEL-регистра

// периферийный блок регистров процессора 177700-177717
assign cpu_dev_stb= cpu_stb_o & local_cyc & (cpu_adr_o[15:4] == (16'o177700 >> 4));   

// ROM с монитором 0000
wire rom_part1 = (cpu_adr_o[12:11] == 2'b00)&(startup_reg[2]|startup_reg[3]);                // область 160000-163777, управляемая битами 2 и 3
wire rom_part2 = ((cpu_adr_o[12:11] == 2'b01)||(cpu_adr_o[12:11] == 2'b10)) & startup_reg[3]; // область 164000-173000 управляемая битом 3
wire rom_part3 = (cpu_adr_o[12:9] == 4'b1011);                                               // область 173000-173777 c загрузчиком,
                                                                                            // всегда отображаемая в адресное пространство
assign rom_stb = cpu_stb_o & local_cyc & (cpu_adr_o[15:13] == 3'b111) & (rom_part1|rom_part2|rom_part3);

// Размещение системной памяти: 177600-177677
assign sysram_stb   = cpu_stb_o & local_cyc &(cpu_adr_o[15:6] == 10'b1111111110); 

// Сигнал подтвреждения обмена - от общей шины и модуля ROM
assign cpu_ack = global_ack | rom_ack | cpu_dev_ack;

// мультиплексор входной шины данных
assign local_dat_i = (rom_stb)?                 rom_dat    : 16'o0    // теневой ROM
                   | (cpu_dev_stb)?             cpu_dev_dat: 16'o0    // периферийный блок процессора
                   | (~rom_stb & ~cpu_dev_stb)? cpu_dat_i  : 16'o0;   // остальные устройства на шине
						 
// Разрешение транзакций на общей шине - только при отсутствии доступа к локальным устройствам
assign cpu_cyc_o=local_cyc & (~rom_stb) & (~cpu_dev_stb);

// Невекторные прерывания
assign		vm_irq[1] = halt;                  // кнопка входа в пульт
assign		vm_irq[2] = timer_50&timer_status; // маскируемое прерывание от часов 50гц
assign		vm_irq[3] = 1'b0;

//************************************************
//* тактовый генератор 
//************************************************
assign busclk  = clk_p;   // тактовая частота шины wishbone

pll100 corepll
(
   .inclk0(clk50),
   .c0(clk_p),     // 100МГц прямая фаза, основная тактовая частота
   .c1(clk_n),     // 100МГц инверсная фаза
   .c2(sdclk),     // 12.5 МГц тактовый сигнал SD-карты
   .locked(clkrdy) // флаг готовности PLL
);

//*************************************
// счетчик замедления процессора
//*************************************
reg [4:0] cpudelay;

always @ (posedge clk_p) begin
    if (cpudelay != 5'd21) cpudelay <= cpudelay + 1'b1;  // считаем от 0 до 22
    else cpudelay <= 5'd0;
end    
wire cpu_clk_enable=~(|cpudelay);  // формирователь импульса с заполнением 1/21

//*************************************
//*  Процессор К1801ВМ1
//*************************************
vm1_wb #(.VM1_CORE_MULG_VERSION(1)) cpu
(
// Синхросигналы  
   .vm_clk_p(clk_p),                // Положительный синхросигнал
   .vm_clk_n(clk_n),                // Отрицательный синхросигнал
   .vm_clk_slow(cpuslow),           // Режим замедления процессора - определяется переключателем 3
   .vm_clk_ena(cpu_clk_enable),     // счетчик замедления
   .vm_clk_tve(1'b1),               // тактовый сигнал встроенного таймера
   .vm_clk_sp(1'b0),                // сигнал захвата таймера

// Шина Wishbone                                       
   .wbm_gnt_i(cpu_gnt_i),           // 1 - разрешение cpu работать с шиной
                                    // 0 - DMA с внешними устройствами, cpu отключен от шины и бесконечно ждет ответа wb_ack
   .wbm_adr_o(cpu_adr_o),           // выход шины адреса
   .wbm_dat_o(cpu_dat_o),           // выход шины данных
   .wbm_dat_i(local_dat_i),         // вход шины данных
   .wbm_cyc_o(local_cyc),           // Строб цила wishbone
   .wbm_we_o(cpu_we_o),             // разрешение записи
   .wbm_sel_o(cpu_sel_o),           // выбор байтов для передачи
   .wbm_stb_o(cpu_stb_o),           // строб данных
   .wbm_ack_i(cpu_ack),             // вход подтверждения данных

// Сбросы и прерывания
   .vm_pa(2'b00),                  	// номер процессора для многопроцессорной конфигурации
   .vm_init_in(1'b0), 			      // вход сброса от ведущего процессора
   .vm_init_out(vm_init),           // Выход сброса для периферии
   .vm_dclo(dclo),                  // Вход сброса процессора
   .vm_aclo(aclo),                  // Сигнал аварии питания
   .vm_irq(vm_irq),	    	      	// запросы фиксированного прерывания
   .vm_virq(virq),                  // Векторное прерывание

// Шины обработки прерываний                                       
   .wbi_dat_i(ivec),                // Шина приема вектора прерывания
   .wbi_stb_o(istb),                // Строб приема вектора прерывания
   .wbi_ack_i(iack),                // Подтверждение приема вектора прерывания

// шина к периферийному блоку
	.wbs_adr_i(cpu_adr_o[3:0]),		// адрес регистра периферийного блока
   .wbs_dat_i(cpu_dat_o),				// вход данных
	.wbs_dat_o(cpu_dev_dat),			// выход данных
	.wbs_cyc_i(local_cyc),				// строб цикла шины
	.wbs_stb_i(cpu_dev_stb),			// строб транзакции
	.wbs_ack_o(cpu_dev_ack),			// подтверждение транзакции
	.wbs_we_i(cpu_we_o),	   			// разрешение записи

//  SEL-регистры
   .vm_reg14(SEL2_even),					// 177714 - SEL2
   .vm_reg16(startup_reg),	 				// 177716 - SEL1, регистр начального запуска	
   .vm_sel(vm_sel)    						// выбирает регистры 14 или 16 соответствующими битами
);

//******************************************************************
//* Модуль ROM с теневым ПЗУ 000
//******************************************************************
wire [15:0] rom_dat;
wire rom_stb;
reg rom_ack;
reg rom_ack0;

rom000 hrom(
   .address(cpu_adr_o[12:1]),
   .clock(clk_p),
   .q(rom_dat)
);
// формирователь cигнала подверждения транзакции с задержкой на 1 такт
always @ (posedge clk_p) begin
   rom_ack0 <= local_cyc & rom_stb;
   rom_ack  <= local_cyc & rom_ack0;
end

//******************************************************************************************
//*  Внешние регистры начального пуска и SEL2, четный и нечетный
//******************************************************************************************

always @(posedge clk_p) begin
	if (dclo) 	begin
	   // сброс регистров сигналом DCLO, до запуска процессора
		SEL2_even <= 16'o000000;
		SEL2_odd <= 16'o000000;

// регистр начального пуска
// D15-D8 - адрес старта процессора
// D0, D1 - режим начального пуска
// D2 - младшая часть теневого ROM
// D3 - старшая часть теневого ROM
		startup_reg <= {14'b11100000000001, `STARTUP};
	end
	// запись регистров
	else begin
		if (vm_sel[2] & cpu_we_o & ~cpu_adr_o[0]) SEL2_even <= cpu_dat_o; // запись четного sel2
		if (vm_sel[2] & cpu_we_o &  cpu_adr_o[0]) SEL2_odd <= cpu_dat_o;  // запись нечетного sel2
		if (vm_sel[1] & cpu_we_o) startup_reg[7:2] <= cpu_dat_o[7:2];  // запись регистра начального пуска

	end
end

//**********************************
//* Сигнал разрешения таймера
//**********************************
initial timer_status=`timer_init;  // начальное состояние таймера
reg [1:0] tbshift;
reg tbevent;

// подавление дребезга кнопки
always @ (posedge timer_50) begin
  // вводим кнопку в сдвиговый регистр
  tbshift[0] <= timer_button;
  tbshift[1] <= tbshift[0];
  // регистр заполнен - кнопка стабильно нажата
  if (&tbshift == 1'b1) begin
      if (tbevent == 1'b0) begin
        timer_status <= ~timer_status;  // переключаем состояние таймера
        tbevent <= 1'b1;                              // запрещаем дальнейшие изменения состояния таймиера
      end
  end
  // регистр очищен - кнопка стабильно отпущена
  else if (|tbshift == 1'b0) tbevent <= 1'b0;     // разрешаем изменения состояния таймера
end  

endmodule
