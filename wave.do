onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -height 19 -expand -group PUSH -color Orange /tb_template/push/clk
add wave -noupdate -height 19 -expand -group PUSH -color Orange /tb_template/push/valid
add wave -noupdate -height 19 -expand -group PUSH -color Orange /tb_template/push/ready
add wave -noupdate -height 19 -expand -group PUSH -color Orange /tb_template/push/data
add wave -noupdate -height 19 -expand -group PUSH -color Orange /tb_template/push/strb
add wave -noupdate -height 19 -expand -group POP -color {Cornflower Blue} /tb_template/pop/clk
add wave -noupdate -height 19 -expand -group POP -color {Cornflower Blue} /tb_template/pop/valid
add wave -noupdate -height 19 -expand -group POP -color {Cornflower Blue} /tb_template/pop/ready
add wave -noupdate -height 19 -expand -group POP -color {Cornflower Blue} /tb_template/pop/data
add wave -noupdate -height 19 -expand -group POP -color {Cornflower Blue} /tb_template/pop/strb
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {22282 ps}
