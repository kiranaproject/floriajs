// Many own properties: exercises shape validation and inline property caches
// beyond the small-object linear-search regime.
var o = { p0: 0, p1: 0, p2: 0, p3: 0, p4: 0, p5: 0, p6: 0, p7: 0, p8: 0, p9: 0, p10: 0, p11: 0, p12: 0, p13: 0, p14: 0, p15: 0, p16: 0, p17: 0, p18: 0, p19: 0, p20: 0, p21: 0, p22: 0, p23: 0, p24: 0, p25: 0, p26: 0, p27: 0, p28: 0, p29: 0, p30: 0, p31: 0, p32: 0, p33: 0, p34: 0, p35: 0, p36: 0, p37: 0, p38: 0, p39: 0 };
var s = 0;
for (var i = 0; i < 5000; i++) {
  o.p39 = o.p39 + 1;
  s = s + o.p39;
}
s;
