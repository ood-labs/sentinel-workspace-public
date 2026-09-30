// Mark index layout shared by marks.hlsl and preview.hlsl. Clip 1 = plan, clip 2 = section.
#define PM_RISER 0      // plan: riser frame
#define PM_BOOTH 1      // 8 booth ring segments
#define PM_PLATE 9      // 6 x (outer edge, inner edge, spoke, sheath edge)
#define PM_COLLAR 33    // collar ring
#define PM_CAP 34       // 36 capsid edges
#define PM_BARS 70      // 768 bar pieces
#define PM_MOUNTS 838   // 176 movers and strobes
#define PM_LEGS 1014    // 6 x (upper, lower, foot, foot ring, edited dot)
#define PM_REACH 1044   // dashed reach circle of the selected leg
#define PS_RISER 1045   // section: riser frame
#define PS_DJ 1046      // DJ body, head
#define PS_BOOTH 1048   // 2 booth points
#define PS_PLATE 1050   // plate frame
#define PS_SHEATH 1051  // 2 sheath posts
#define PS_RINGS 1053   // 5 sheath rings
#define PS_COLLAR 1058  // collar frame
#define PS_CAP 1059     // 36 capsid edges
#define PS_LEGS 1095    // 2 legs x (upper, lower, spike, spike)
#define PS_SEL 1103     // selected leg: dashed upper-length circle, knee ring, hip dot
#define PM_MARKS 1106
#define PM_REC 1106     // records in fill: counts (movers, strobes, bars, 1), leg (upper, lower, reach %, broken), (lip, section leg)
#define PM_TOTAL 1109
