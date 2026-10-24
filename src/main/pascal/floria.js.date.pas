{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in Date Support                           }
{                                                                          }
{   Provides standard JavaScript Date object, Date.now(), Date.parse(),    }
{   UTC/local date component getters/setters, and ISO-8601 formatting.     }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.date;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils, floria.js.types, floria.js.value, floria.js.env;

procedure FloriaJSRegisterDate(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

const
  UNIX_EPOCH_DATETIME = 25569.0; { TDateTime value for 1970-01-01 00:00:00 UTC }
  MS_PER_DAY = 86400000.0;

function CurrentEpochMS(): Double;
var
  nowUTC: TDateTime;
begin
  nowUTC := Now() - (GetLocalTimeOffset() / (24.0 * 60.0));
  Result := (nowUTC - UNIX_EPOCH_DATETIME) * MS_PER_DAY;
end;

function EpochMSToUTCDateTime(AMS: Double): TDateTime;
begin
  Result := (AMS / MS_PER_DAY) + UNIX_EPOCH_DATETIME;
end;

function EpochMSToLocalDateTime(AMS: Double): TDateTime;
var
  utcDT: TDateTime;
begin
  utcDT := EpochMSToUTCDateTime(AMS);
  Result := utcDT + (GetLocalTimeOffset() / (24.0 * 60.0));
end;

function LocalDateTimeToEpochMS(ADT: TDateTime): Double;
var
  utcDT: TDateTime;
begin
  utcDT := ADT - (GetLocalTimeOffset() / (24.0 * 60.0));
  Result := (utcDT - UNIX_EPOCH_DATETIME) * MS_PER_DAY;
end;

function ParseISODateString(const AStr: string): Double;
var
  s: string;
  y, m, d, hh, mm, ss, ms: Integer;
  parts: TStringArray;
  timePart: string;
begin
  s := Trim(AStr);
  y := 1970; m := 1; d := 1; hh := 0; mm := 0; ss := 0; ms := 0;

  if Pos('T', s) > 0 then
  begin
    parts := s.Split(['T']);
    if Length(parts) >= 2 then
    begin
      // Date part YYYY-MM-DD
      sscanf(PChar(parts[0]), '%d-%d-%d', [@y, @m, @d]);
      timePart := parts[1];
      if (Length(timePart) > 0) and (timePart[Length(timePart)] = 'Z') then
        SetLength(timePart, Length(timePart) - 1);

      // Time part HH:mm:ss.ms
      if Pos('.', timePart) > 0 then
        sscanf(PChar(timePart), '%d:%d:%d.%d', [@hh, @mm, @ss, @ms])
      else
        sscanf(PChar(timePart), '%d:%d:%d', [@hh, @mm, @ss]);

      Result := (EncodeDateTime(y, m, d, hh, mm, ss, ms) - UNIX_EPOCH_DATETIME) * MS_PER_DAY;
      Exit;
    end;
  end
  else if Pos('-', s) > 0 then
  begin
    if sscanf(PChar(s), '%d-%d-%d', [@y, @m, @d]) = 3 then
    begin
      Result := (EncodeDateTime(y, m, d, 0, 0, 0, 0) - UNIX_EPOCH_DATETIME) * MS_PER_DAY;
      Exit;
    end;
  end;

  Result := CurrentEpochMS();
end;

function GetDateMS(AObj: TFloriaJSValue): Double;
begin
  if AObj.IsObject() and (AObj.ObjVal <> nil) then
    Result := AObj.ObjVal.GetProperty('__date_ms__').ToNumber()
  else
    Result := NaN;
end;

procedure SetDateMS(AObj: TFloriaJSValue; AMS: Double);
begin
  if AObj.IsObject() and (AObj.ObjVal <> nil) then
    AObj.ObjVal.SetProperty('__date_ms__', JSMakeNumber(AMS));
end;

{ Date Constructor }
function JSDateCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
  dt: TDateTime;
  y, m, d, hh, mm, ss, msec: Integer;
begin
  // When called as a function (not constructor), return string of current time
  if not AThis.IsObject() or (AThis.ObjVal = nil) then
    Exit(JSMakeString(DateTimeToStr(Now())));

  case Length(AArgs) of
    0:
      ms := CurrentEpochMS();
    1:
      begin
        if AArgs[0].IsNumber() then
          ms := AArgs[0].NumVal
        else if AArgs[0].IsString() then
          ms := ParseISODateString(AArgs[0].StrVal)
        else
          ms := AArgs[0].ToNumber();
      end;
  else
    y := Round(AArgs[0].ToNumber());
    m := Round(AArgs[1].ToNumber()) + 1; // JS months are 0..11
    if Length(AArgs) > 2 then d := Round(AArgs[2].ToNumber()) else d := 1;
    if Length(AArgs) > 3 then hh := Round(AArgs[3].ToNumber()) else hh := 0;
    if Length(AArgs) > 4 then mm := Round(AArgs[4].ToNumber()) else mm := 0;
    if Length(AArgs) > 5 then ss := Round(AArgs[5].ToNumber()) else ss := 0;
    if Length(AArgs) > 6 then msec := Round(AArgs[6].ToNumber()) else msec := 0;

    if TryEncodeDateTime(y, m, d, hh, mm, ss, msec, dt) then
      ms := LocalDateTimeToEpochMS(dt)
    else
      ms := NaN;
  end;

  SetDateMS(AThis, ms);
  Result := AThis;
end;

{ Date.now() }
function JSDateNow(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(CurrentEpochMS());
end;

{ Date.parse() }
function JSDateParse(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(ParseISODateString(AArgs[0].ToString()));
end;

{ Date.UTC(year, monthIndex, ...) }
function JSDateUTC(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  y, m, d, hh, mm, ss, msec: Integer;
  dt: TDateTime;
begin
  if Length(AArgs) < 2 then
    Exit(JSMakeNumber(NaN));

  y := Round(AArgs[0].ToNumber());
  m := Round(AArgs[1].ToNumber()) + 1;
  if Length(AArgs) > 2 then d := Round(AArgs[2].ToNumber()) else d := 1;
  if Length(AArgs) > 3 then hh := Round(AArgs[3].ToNumber()) else hh := 0;
  if Length(AArgs) > 4 then mm := Round(AArgs[4].ToNumber()) else mm := 0;
  if Length(AArgs) > 5 then ss := Round(AArgs[5].ToNumber()) else ss := 0;
  if Length(AArgs) > 6 then msec := Round(AArgs[6].ToNumber()) else msec := 0;

  if TryEncodeDateTime(y, m, d, hh, mm, ss, msec, dt) then
    Result := JSMakeNumber((dt - UNIX_EPOCH_DATETIME) * MS_PER_DAY)
  else
    Result := JSMakeNumber(NaN);
end;

{ Prototype Methods }

function JSDateGetTime(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(GetDateMS(AThis));
end;

function JSDateSetTime(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  if Length(AArgs) = 0 then
    ms := NaN
  else
    ms := AArgs[0].ToNumber();
  SetDateMS(AThis, ms);
  Result := JSMakeNumber(ms);
end;

function JSDateGetFullYear(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(YearOf(EpochMSToLocalDateTime(ms)));
end;

function JSDateGetUTCFullYear(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(YearOf(EpochMSToUTCDateTime(ms)));
end;

function JSDateGetMonth(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(MonthOf(EpochMSToLocalDateTime(ms)) - 1);
end;

function JSDateGetUTCMonth(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(MonthOf(EpochMSToUTCDateTime(ms)) - 1);
end;

function JSDateGetDate(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(DayOf(EpochMSToLocalDateTime(ms)));
end;

function JSDateGetUTCDate(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(DayOf(EpochMSToUTCDateTime(ms)));
end;

function JSDateGetDay(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(DayOfWeek(EpochMSToLocalDateTime(ms)) - 1); // FPC Sunday=1 -> JS Sunday=0
end;

function JSDateGetUTCDay(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(DayOfWeek(EpochMSToUTCDateTime(ms)) - 1);
end;

function JSDateGetHours(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(HourOf(EpochMSToLocalDateTime(ms)));
end;

function JSDateGetUTCHours(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(HourOf(EpochMSToUTCDateTime(ms)));
end;

function JSDateGetMinutes(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(MinuteOf(EpochMSToLocalDateTime(ms)));
end;

function JSDateGetUTCMinutes(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(MinuteOf(EpochMSToUTCDateTime(ms)));
end;

function JSDateGetSeconds(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(SecondOf(EpochMSToLocalDateTime(ms)));
end;

function JSDateGetUTCSeconds(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(SecondOf(EpochMSToUTCDateTime(ms)));
end;

function JSDateGetMilliseconds(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(MilliSecondOf(EpochMSToLocalDateTime(ms)));
end;

function JSDateGetUTCMilliseconds(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(MilliSecondOf(EpochMSToUTCDateTime(ms)));
end;

function JSDateGetTimezoneOffset(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  // JS timezone offset is in minutes, opposite sign of UTC offset
  Result := JSMakeNumber(-GetLocalTimeOffset());
end;

function JSDateToISOString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
  dt: TDateTime;
  y, m, d, hh, mm, ss, msec: Word;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('RangeError', 'Invalid time value')));

  dt := EpochMSToUTCDateTime(ms);
  DecodeDate(dt, y, m, d);
  DecodeTime(dt, hh, mm, ss, msec);

  Result := JSMakeString(Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.3dZ', [y, m, d, hh, mm, ss, msec]));
end;

function JSDateToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
  dt: TDateTime;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeString('Invalid Date'));

  dt := EpochMSToLocalDateTime(ms);
  Result := JSMakeString(FormatDateTime('ddd mmm dd yyyy hh:nn:ss', dt));
end;

function JSDateToDateString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
  dt: TDateTime;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeString('Invalid Date'));

  dt := EpochMSToLocalDateTime(ms);
  Result := JSMakeString(FormatDateTime('ddd mmm dd yyyy', dt));
end;

function JSDateToTimeString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  ms: Double;
  dt: TDateTime;
begin
  ms := GetDateMS(AThis);
  if IsNaN(ms) then Exit(JSMakeString('Invalid Date'));

  dt := EpochMSToLocalDateTime(ms);
  Result := JSMakeString(FormatDateTime('hh:nn:ss', dt));
end;

procedure FloriaJSRegisterDate(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  dateCtor: TFloriaJSFunction;
  dateProto: TFloriaJSObject;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  dateProto := AHeap.NewObject();
  dateProto.SetProperty('getTime', JSMakeFunction(AHeap.NewNativeFunction('getTime', @JSDateGetTime)));
  dateProto.SetProperty('valueOf', JSMakeFunction(AHeap.NewNativeFunction('valueOf', @JSDateGetTime)));
  dateProto.SetProperty('setTime', JSMakeFunction(AHeap.NewNativeFunction('setTime', @JSDateSetTime)));

  dateProto.SetProperty('getFullYear', JSMakeFunction(AHeap.NewNativeFunction('getFullYear', @JSDateGetFullYear)));
  dateProto.SetProperty('getUTCFullYear', JSMakeFunction(AHeap.NewNativeFunction('getUTCFullYear', @JSDateGetUTCFullYear)));
  dateProto.SetProperty('getMonth', JSMakeFunction(AHeap.NewNativeFunction('getMonth', @JSDateGetMonth)));
  dateProto.SetProperty('getUTCMonth', JSMakeFunction(AHeap.NewNativeFunction('getUTCMonth', @JSDateGetUTCMonth)));
  dateProto.SetProperty('getDate', JSMakeFunction(AHeap.NewNativeFunction('getDate', @JSDateGetDate)));
  dateProto.SetProperty('getUTCDate', JSMakeFunction(AHeap.NewNativeFunction('getUTCDate', @JSDateGetUTCDate)));
  dateProto.SetProperty('getDay', JSMakeFunction(AHeap.NewNativeFunction('getDay', @JSDateGetDay)));
  dateProto.SetProperty('getUTCDay', JSMakeFunction(AHeap.NewNativeFunction('getUTCDay', @JSDateGetUTCDay)));
  dateProto.SetProperty('getHours', JSMakeFunction(AHeap.NewNativeFunction('getHours', @JSDateGetHours)));
  dateProto.SetProperty('getUTCHours', JSMakeFunction(AHeap.NewNativeFunction('getUTCHours', @JSDateGetUTCHours)));
  dateProto.SetProperty('getMinutes', JSMakeFunction(AHeap.NewNativeFunction('getMinutes', @JSDateGetMinutes)));
  dateProto.SetProperty('getUTCMinutes', JSMakeFunction(AHeap.NewNativeFunction('getUTCMinutes', @JSDateGetUTCMinutes)));
  dateProto.SetProperty('getSeconds', JSMakeFunction(AHeap.NewNativeFunction('getSeconds', @JSDateGetSeconds)));
  dateProto.SetProperty('getUTCSeconds', JSMakeFunction(AHeap.NewNativeFunction('getUTCSeconds', @JSDateGetUTCSeconds)));
  dateProto.SetProperty('getMilliseconds', JSMakeFunction(AHeap.NewNativeFunction('getMilliseconds', @JSDateGetMilliseconds)));
  dateProto.SetProperty('getUTCMilliseconds', JSMakeFunction(AHeap.NewNativeFunction('getUTCMilliseconds', @JSDateGetUTCMilliseconds)));
  dateProto.SetProperty('getTimezoneOffset', JSMakeFunction(AHeap.NewNativeFunction('getTimezoneOffset', @JSDateGetTimezoneOffset)));

  dateProto.SetProperty('toISOString', JSMakeFunction(AHeap.NewNativeFunction('toISOString', @JSDateToISOString)));
  dateProto.SetProperty('toUTCString', JSMakeFunction(AHeap.NewNativeFunction('toUTCString', @JSDateToISOString)));
  dateProto.SetProperty('toString', JSMakeFunction(AHeap.NewNativeFunction('toString', @JSDateToString)));
  dateProto.SetProperty('toDateString', JSMakeFunction(AHeap.NewNativeFunction('toDateString', @JSDateToDateString)));
  dateProto.SetProperty('toTimeString', JSMakeFunction(AHeap.NewNativeFunction('toTimeString', @JSDateToTimeString)));

  dateCtor := AHeap.NewNativeFunction('Date', @JSDateCtor);
  dateCtor.SetProperty('prototype', JSMakeObject(dateProto));
  dateCtor.SetProperty('now', JSMakeFunction(AHeap.NewNativeFunction('now', @JSDateNow)));
  dateCtor.SetProperty('parse', JSMakeFunction(AHeap.NewNativeFunction('parse', @JSDateParse)));
  dateCtor.SetProperty('UTC', JSMakeFunction(AHeap.NewNativeFunction('UTC', @JSDateUTC)));

  AEnv.Define('Date', JSMakeFunction(dateCtor));
end;

end.
