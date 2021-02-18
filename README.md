# mc1201-02
FPGA-версия старых советских микро-ЭВМ ДВК-1, ДВК-2, ДВК-3, Электроника-60

Этот проект является моей попыткой создать FPGA-версию советских микро-ЭВМ, основанных на процессорных ядрах от уважаемого VLSAV, полученных им путем реверса схемы кристаллов.
Проект основан на wishbone-версии процессоров. Вся внутренняя шина получившейся схемы - это тоже wishbone, а не асинхронная МПИ. в данный момент реализованы следующие процессорные платы:

  Плата       Процессор     ЭВМ           Тактовая частота
-------------------------------------------------------------
  МС1201.01   К1801ВМ1     ДВК-1,ДВК-2       100 Мгц
  МС1201.02   К1801ВМ2     ДВК-3             100 Мгц
  МС1260      М2 (LSI-11)  Электроника-60    100 Мгц
  МС1280      М4 (LSI-11M)                    50 МГц
------------------------------------------------------------

Как и в оригинальных ЭВМ, на верхнем уровне схемы находится соединительная корзина, в которую вставляется одна процессорная плата и несколько плат периферийных устройств. На данный момент реализованы следующие устройства:

- ИРПС, контроллер последовательной передачи данных, используется в том числе для подключения консольного терминала
- ИРПР, контроллер параллельной передачи, для поключения принтера
- КСМ, терминальный моудль, работает с VGA-мониторами и PS/2 клавиатурой.
- КГД, графический контроллер, работает в паре с КСМ
- Контроллер RK11 (RK:) с подключенными у нему 8 дисками RK05
- Контроллер HDD RD50C (DW:) в варианте ДВК с подключенным к нему виртуальным HDD объемом 64 Мб.
- Контроллер RX11 (DX:)  с подключенными к нему двумя дисководами RX01 (наш аналог - ГМД70)
- Контроллер КГД (MY:) с подключенными к нему двумя сдвоенными дисководами НГМД-6121
- Контроллер синхронной динамической памяти SDRAM
- ПЗУ пользователя размером 8К (в ДВК-1 там размещался резидентный Бейсик или Фокал).

Все дисковые контроллеры хранят свои данные на единой SD-карте, но можно разнести их и по отдельным картам. Карту распределения блоков под дисковые массивы также можно менять как угодно.
Кроме вышеуказанных модулей, в схему можно добавлять и свои самодельные модули с wishbone-интерфейсом.

Эта разработка с середины лета 2020 года успешно трудится в лаборатории в качестве контроллера испытательного стенда и показала полную работоспособность. Все, кому надо заменить устаревшее оборудование, основанное на плате МС1201, МС1260, МС1280,могут доработать схему под свои конкретные нужды.
