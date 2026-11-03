# Queue

| Milestones | Depends on | Note |
|------------|------------|------|
| UTERM-009 M1-M4 | None | |
| UTERM-008 M1-M2 | None | Split at M2: M3 needs the exec driver and applet command hook from UTERM-004 M3 |
| UTERM-005 M1-M7 | None | Split at M7: M8 needs the control permissions from UTERM-004 M6 |
| UTERM-003 M1-M5 | None | |
| UTERM-004 M1-M6 | UTERM-003 | Needs the host API and listener UTERM-003 builds. Placed right after it to close the same-user control window UTERM-003 M3 opens |
| UTERM-008 M3 | UTERM-004 M3 | Split from M1-M2: waits on the exec driver and applet command hook from UTERM-004 M3 |
| UTERM-005 M8 | UTERM-004 M6 | Split from M1-M7: waits on UTERM-004 M6 and its browser-permission amendment |
