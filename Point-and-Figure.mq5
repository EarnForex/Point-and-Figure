//+------------------------------------------------------------------+
//|                                             Point-and-Figure.mq5 |
//|                                  Copyright © 2022, EarnForex.com |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2022, www.EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/Point-and-Figure-Indicator/"
#property version   "1.00"

#property description "Point-and-Figure is a basic point-and-figure charting indicator based on real ticks data."
#property description "It supports full customization and all types of alerts."

#property indicator_chart_window
#property indicator_plots 0

// Define directions:
#define NONE 0
#define UP 1
#define DOWN -1

enum enum_price
{
    Bid,
    Ask,
    Midprice,
    BidAsk // Bid/Ask 
    
};

input int BoxSize  = 60; // Box size, points
input int Reversal = 3; // Number of boxes for reversal
input int Days = 1; // Days to look back.
input enum_price PriceToUse = Bid; // Price to use
input bool AlertOnXO = false; // Alert on new X/O
input bool AlertOnReversal = false; // Alert on reversal
input bool EnableNativeAlerts = false; // Enable native alerts
input bool EnableEmailAlerts = false; // Enable email alerts
input bool EnablePushAlerts = false; // Enable push-notification alerts
input color ColorUp   = clrGreen;     // X Color
input color ColorDown = clrRed;   // O Color
input int FontSize = 15; // Font size
input string Font = "Arial"; // Font
input string X = "x"; // Up Symbol
input string O = "o"; // Down Symbol
input bool SilentMode = true; // Don't print information about each X/O
input int MaxObjects = 10000; // Maximum allowed number of X/O chart objects
input string ObjectPrefix = "PNF-";

// Converted parameters:
double cBoxSize;
double cReversal;

double LastPrice; // Stores last price where a box was drawn.
double CurrentDirection;
double FirstBoxUp;
double FirstBoxDown;

ulong LastEndTime_msc;
int Number; // Number of objects.

int LastBars; // Number of bars.
datetime LastBarTime; // To check if it were some old bars downloading or new ones.

int OnInit()
{
    Number = 0;
    LastBars = 0;
    LastPrice = 0;
    CurrentDirection = NONE;
    FirstBoxUp = 0;
    FirstBoxDown = 0;
    LastEndTime_msc = 0;
    LastBarTime = 0;
    
    cBoxSize = BoxSize * _Point;
    cReversal = Reversal * cBoxSize;

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(ChartID(), ObjectPrefix);
    ChartRedraw();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &Time[],
                const double &Open[],
                const double &High[],
                const double &Low[],
                const double &Close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (iBarShift(Symbol(), Period(), iTime(Symbol(), Period(), 0), true) < 0) // iBarShift failure.
    {
        // When chart data is in normal state, there shouldn't be an error when searching for the current bar with iBarShift.
        return prev_calculated;
    }
    if ((LastBars < rates_total) && (LastBars != 0) && (LastBarTime != Time[rates_total - 1]))
    {
        if (Number > MaxObjects) Print("Warning: Too many X/O objects!");
        while (LastBars < rates_total)
        {   
            MoveAllRight();
            LastBars++;
        }
        LastBarTime = Time[rates_total - 1]; // Remember current bar time.
    }
    LastBars = rates_total;

    MqlTick ticks_array[];
    int end_time_seconds = (int)TimeCurrent();
    ulong begin_time_msc;
    if (LastEndTime_msc == 0)
    {
        begin_time_msc = ulong(end_time_seconds - Days * 24 * 3600) * 1000; // First time.
        if (begin_time_msc / 1000 < (ulong)Time[0]) // Time[0] - oldest bar.
        {
            Print("Requested Days go beyond the available chart data. Either reduce Days or load more bars.");
            return prev_calculated;
        }
    }
    else begin_time_msc = LastEndTime_msc + 1;
    // CopyTicks() has inconsistent behavior, so everything is handled with CopyTicksRange().
    int n = CopyTicksRange(Symbol(), ticks_array, COPY_TICKS_ALL, begin_time_msc, (ulong)end_time_seconds * 1000);
    if (n < 0)
    {
        Print("Waiting for ticks... ");
        return prev_calculated;
    }
    else if (n == 0)
    {
        return rates_total; // No new ticks.
    }
    else
    {
        LastEndTime_msc = ticks_array[n - 1].time_msc;
    }

    for (int i = 0; i < n; i++)
    {
        double Price = 0, B = 0, A = 0;
        switch (PriceToUse)
        {
            case Bid:
            Price = ticks_array[i].bid;
            break;
            case Ask:
            Price = ticks_array[i].ask;
            break;
            case Midprice:
            Price = (ticks_array[i].bid + ticks_array[i].ask) / 2;
            break;
            case BidAsk: // Difficult case - use Bid for X's and Ask for O's.
            B = ticks_array[i].bid;
            A = ticks_array[i].ask;
            break;
            default:
            Price = 0;
            A = 0;
            B = 0;
            break;
        }        
        
        if (CurrentDirection == NONE)
        {
            // Draw first X:
            if (PriceToUse == BidAsk) Price = B;
            if ((Price >= FirstBoxUp) && (FirstBoxUp != 0))
            {
                LastPrice = FirstBoxUp;
                while (LastPrice <= Price) // Grow a stack of X's until the next X would be above the current Bid.
                {
                    DrawX(LastPrice);
                    if ((AlertOnXO) && (TimeCurrent() - ticks_array[i].time <= 5)) DoAlerts("X"); // Within last 5 seconds.
                    LastPrice = NormalizeDouble(LastPrice + cBoxSize, _Digits);
                }
            }
            // Draw first O:
            else 
            {
                if (PriceToUse == BidAsk) Price = A;
                if ((Price <= FirstBoxDown) && (FirstBoxDown != 0))
                {
                    LastPrice = FirstBoxDown;
                    while (LastPrice >= Price) // Put down O's until the next O would be below the current Bid.
                    {
                        DrawO(LastPrice);
                        if ((AlertOnXO) && (TimeCurrent() - ticks_array[i].time <= 5)) DoAlerts("O"); // Within last 5 seconds.
                        LastPrice = NormalizeDouble(LastPrice - cBoxSize, _Digits);
                    }
                }
            }
            // Set boundaries for the first X/O:
            if (FirstBoxUp == 0)
            {
                if (PriceToUse == BidAsk) Price = B;
                FirstBoxUp = NormalizeDouble(MathCeil(Price / cBoxSize) * cBoxSize, _Digits);
            }
            if (FirstBoxDown == 0)
            {
                if (PriceToUse == BidAsk) Price = A;
                FirstBoxDown = NormalizeDouble(MathFloor(Price / cBoxSize) * cBoxSize, _Digits);
            }
        }
        // Subsequent X/O should be drawn on normalized levels only.
        else if (CurrentDirection == UP)
        {
            if (PriceToUse == BidAsk) Price = B;
            while (Price >= LastPrice) // Grow a stack of X's until the next X would be above the current Bid.
            {
                DrawX(LastPrice);
                if ((AlertOnXO) && (TimeCurrent() - ticks_array[i].time <= 5)) DoAlerts("X"); // Within last 5 seconds.
                LastPrice = NormalizeDouble(LastPrice + cBoxSize, _Digits);
            }
            if (Price <= LastPrice - cBoxSize - cReversal) // - cBoxSize because LastPrice has already been incremented.
            {
                if ((AlertOnReversal) && (TimeCurrent() - ticks_array[i].time <= 5)) DoAlerts("X->O Reversal"); // Within last 5 seconds.
                LastPrice = NormalizeDouble(LastPrice - 2 * cBoxSize, _Digits); // First reversal O is drawn below the last X.
                while (Price <= LastPrice)
                {
                    DrawO(LastPrice);
                    LastPrice = NormalizeDouble(LastPrice - cBoxSize, _Digits);
                }
            }
        }
        else if (CurrentDirection == DOWN)
        {
            if (PriceToUse == BidAsk) Price = A;
            while (Price <= LastPrice) // Put down O's until the next O would be below the current Bid.
            {
                DrawO(LastPrice);
                if ((AlertOnXO) && (TimeCurrent() - ticks_array[i].time <= 5)) DoAlerts("O"); // Within last 5 seconds.
                LastPrice = NormalizeDouble(LastPrice - cBoxSize, _Digits);
            }
            if (Price >= LastPrice + cBoxSize + cReversal)
            {
                if ((AlertOnReversal) && (TimeCurrent() - ticks_array[i].time <= 5)) DoAlerts("O->X Reversal"); // Within last 5 seconds.
                LastPrice = NormalizeDouble(LastPrice + cBoxSize * 2, _Digits); // First reversal X is drawn above the last O.
                while (Price >= LastPrice)
                {
                    DrawX(LastPrice);
                    LastPrice = NormalizeDouble(LastPrice + cBoxSize, _Digits);
                }
            }
        }
        if (Number > MaxObjects) break;
    }
    return rates_total;
}

void DrawX(double price)
{
    if (CurrentDirection == DOWN) MoveAllLeft(); // Reversal - need to form a new column.

    ObjectCreate(ChartID(), ObjectPrefix + IntegerToString(Number), OBJ_TEXT, 0, iTime(Symbol(), Period(), 0), price);

    ObjectSetString(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_TEXT, X);
    ObjectSetInteger(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_FONTSIZE, FontSize);
    ObjectSetString(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_FONT, Font);
    ObjectSetInteger(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_COLOR, ColorUp);
    
    Number++;
    CurrentDirection = UP;
    
    if (!SilentMode) Print("X: ", price);
}

void DrawO(double price)
{
    if (CurrentDirection == UP) MoveAllLeft(); // Reversal - need to form a new column

    ObjectCreate(ChartID(), ObjectPrefix + IntegerToString(Number), OBJ_TEXT, 0, iTime(Symbol(), Period(), 0), price);

    ObjectSetString(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_TEXT, O);
    ObjectSetInteger(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_FONTSIZE, FontSize);
    ObjectSetString(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_FONT, Font);
    ObjectSetInteger(ChartID(), ObjectPrefix + IntegerToString(Number), OBJPROP_COLOR, ColorDown);
    
    Number++;
    CurrentDirection = DOWN;

    if (!SilentMode) Print("O: ", price);
}

void MoveAllRight()
{
    if (!SilentMode) Print("Moving all X/O to the right...");
    for (int i = 0; i < Number; i++)
    {
        datetime pt = (int)ObjectGetInteger(ChartID(), ObjectPrefix + IntegerToString(i), OBJPROP_TIME, 0);
        int bar = iBarShift(Symbol(), Period(), pt, true);
        if (bar > 0) bar--;
        else if (bar == 0) Print("Can't move right!");
        else if (bar < 0) Print("iBarShift error! ", __FUNCTION__, " ", pt);
        pt = iTime(Symbol(), Period(), bar);
        ObjectSetInteger(ChartID(), ObjectPrefix + IntegerToString(i), OBJPROP_TIME, 0, (int)pt);
    }
}

void MoveAllLeft()
{
    if (!SilentMode) Print("Moving all X/O to the left...");
    int max_bar = iBars(Symbol(), Period()) - 1;
    for (int i = 0; i < Number; i++)
    {
        datetime pt = (datetime)ObjectGetInteger(ChartID(), ObjectPrefix + IntegerToString(i), OBJPROP_TIME, 0);
        int bar = iBarShift(Symbol(), Period(), pt, true);
        if (bar == -1)
        {
            Print("iBarShift error! ", __FUNCTION__, " ", pt);
            return;
        }
        else if (bar < max_bar) bar++;
        else
        {
            Print("Failed to increment the bar value: bar ", bar, " >= ", max_bar);
            return;
        }
        pt = iTime(Symbol(), Period(), bar);
        if (pt == 0) Print(bar);
        ObjectSetInteger(ChartID(), ObjectPrefix + IntegerToString(i), OBJPROP_TIME, 0, (int)pt);
    }
}

void DoAlerts(string text)
{
    string Text, TextNative;
    Text = "Point-and-Figure: " + Symbol() + " - " + text + " @ " + DoubleToString(LastPrice, _Digits);
    TextNative = text + " @ " + DoubleToString(LastPrice, _Digits);
    if (EnableNativeAlerts) Alert(TextNative);
    if (EnableEmailAlerts) SendMail("Point-and-Figure Alert", Text);
    if (EnablePushAlerts) SendNotification(Text);
}
//+------------------------------------------------------------------+