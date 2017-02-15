# register allocation
#
# ra0...ra7                                     eight horizontal filter coefficients
#
# rb0 rx_shift2
# rb1 ra_y2_next
#
# rb4...rb7
#
# ra8...ra15                                    eight filtered rows of context (rb15 == most recent)
#
#                                               (ra15 isn't clamped to zero - this happens during the
#                                                copy to ra14, and during its use in the vertical filter)
#
# rb8...rb11                                    eight vertical filter coefficients

# ra4                                           y: Fiter, UV: 0x10000

# rb12                                          offset to add before shift (round + weighting offsets)
# rb13                                          shift Y:(denom + 6 + 8), UV:(denom + 6 + 9)
# rb14                                          L0 weight (U on left, V on right)
# rb15                                          -- free --
#
# ra16                                          clipped(row start address+elem_num)&~3
# ra17                                          per-channel shifts
# ra18                                          L1 weight (Y)
# ra19                                          next ra17
#
# rb16                                          pitch
# rb17                                          height + 1
# rb18                                          height + 3
# rb19                                          next ra16
#
# ra20                                          1
# ra21                                          ra_21
# ra22 ra_k256                                  256
# ra23                                          rx_shift2_next
#
# rb20                                          0xffffff00
# rb21                                          vpm_setup for reading/writing 16bit results into VPM
# rb22 rb_k255                                  255
# rb23                                          24
#
# rb24                                          vdw_setup_1(dst_pitch)
# rb25                                          frame width-1
# rb26                                          height<<23 + width<<16 + vdw_setup_0
# rb27                                          vdw_setup_0 (depends on QPU number)
# rb28                                          vpm_setup (depends on QPU number) for writing 8bit results into VPM
# rb29                                          vdw_setup_1(dst_pitch-width)
# rb30                                          frame height-1
# rb31                                          used as temp to count loop iterations
#
# ra24                                          clipped(row start address+8+elem_num)&~3
# ra25                                          per-channel shifts 2
# ra26                                          next ra24
# ra27                                          next ra25
# ra28                                          next y
# ra29                                          y for next texture access
# ra30                                          64
#
# ra31                                          next kernel address

.set rb_frame_width_minus_1,       rb25
.set rb_frame_height_minus_1,      rb30
.set rb_pitch,                     rb16
.set ra_x,                         ra16
.set ra_y2,                        ra21
.set ra_y2_next,                   rb1

.set rb_x_next,                    rb19
.set rx_frame_base2_next,          rb19

.set ra_frame_base,                ra24
.set ra_frame_base_next,           ra26
.set ra_xshift,                    ra17

.set ra_u2v_ref_offset,            ra25
.set ra_frame_base2,               ra25

.set ra_xshift_next,               ra19
.set rx_xshift2,                   rb0
.set rx_xshift2_next,              ra23

.set ra_x2shift_next,              ra27
.set ra_u2v_dst_offset,            ra27

.set ra_y_next,                    ra28
.set ra_y,                         ra29

.set rb_k255,                      rb22
.set ra_k256,                      ra22

# With shifts only the bottom 5 bits are considered so -16=16, -15=17 etc.
.set i_shift16,                    -16

################################################################################
# mc_setup_uv(next_kernel, x, y, ref_u_base, ref_v_base, frame_width, frame_height, pitch, dst_pitch, offset, denom, vpm_id)
::mc_setup_uv

# Read starting kernel
mov ra31, unif

# Load first request location
add ra_x, unif, elem_num # Store x
mov ra_y, unif # Store y
mov ra_frame_base, unif # Store frame u base
nop
sub ra_u2v_ref_offset, unif, ra_frame_base # Store offset to add to move from u to v in reference frame

# Read image dimensions
sub rb25,unif,1
sub rb30,unif,1

# get source pitch
mov rb16, unif

# get destination pitch
mov r0, unif
mov r1, vdw_setup_1(0)
add rb24, r1, r0

# load constants

mov ra4, 0x10000
mov ra20, 1
mov ra_k256, 256
mov ra30, 64

mov rb20, 0xffffff00
mov rb_k255, 255
mov rb23, 24

# touch vertical context to keep simulator happy

mov ra8, 0
mov ra9, 0
mov ra10, 0
mov ra11, 0
mov ra12, 0
mov ra13, 0
mov ra14, 0
mov ra15, 0

# Compute base address for first and second access
mov r0, ra_x           # Load x
max r0, r0, 0; mov r1, ra_y # Load y
min r0, r0, rb_frame_width_minus_1 ; mov r3, ra_frame_base  # Load the frame base
shl ra_xshift_next, r0, 3 ; mov r2, ra_u2v_ref_offset
add ra_y, r1, 1
add r0, r0, r3
and r0, r0, ~3
max r1, r1, 0 ; mov ra_x, r0 # y
min r1, r1, rb_frame_height_minus_1
# submit texture requests for first line
add r2, r2, r0 ; mul24 r1, r1, rb_pitch
add t0s, r0, r1 ; mov ra_frame_base, r2
add t1s, r2, r1

mov r2, 9
add rb13, r2, unif  # denominator
mov -, unif         # Unused

# Compute part of VPM to use for DMA output
mov r2, unif
shl r2, r2, 1   # Convert QPU numbers to be even (this means we can only use 8 QPUs, but is necessary as we need to save 16bit intermediate results)
and r2, r2, 15
mov r1, r2
asr r1, r1, 2
shl r1, r1, 6
mov r0, r2
and r0, r0, 3
add r0, r0, r1

mov r1, vpm_setup(0, 4, h8p(0, 0))   # 4 is stride - stride acts on ADDR which is Y[5:0],B[1:0] for 8 bit
add rb28, r0, r1  # VPM 8bit storage
asr r2, r0, 1     # r0 = bc0000d
mov r1, vpm_setup(0, 2, h16p(0, 0))  # 2 is stride - stride acts on ADDR which is Y[5:0],H[0] for 16 bit
add rb21, r2, r1  # VPM for 16bit intermediates
mov r1, vdw_setup_0(0, 0, dma_h8p(0,0,0)) # height,width added later
shl r0, r0, 5
add rb27, r0, r1  # DMA out

# submit texture requests for second line
max r1, ra_y, 0
min r1, r1, rb_frame_height_minus_1
add ra_y, ra_y, 1
bra -, ra31
nop ; mul24 r1, r1, rb_pitch
add t0s, r1, ra_x
add t1s, r1, ra_frame_base



################################################################################

# mc_filter_uv(next_kernel, x, y, frame_u_base, frame_v_base, width_height, hcoeffs, vcoeffs, offset_weight_u, offset_weight_v, this_u_dst, this_v_dst)

# At this point we have already issued two pairs of texture requests for the current block
# ra_x, ra_x16_base point to the current coordinates for this block
::mc_filter_uv
mov ra31, unif

# per-channel shifts were calculated on the *previous* invocation

# get base addresses and per-channel shifts for *next* invocation
add r0, unif, elem_num    # x
max r0, r0, 0         ; mov r1, unif # y
min r0, r0, rb_frame_width_minus_1 ; mov r3, unif # frame_base
# compute offset from frame base u to frame base v
sub r2, unif, r3      ; mov ra_xshift, ra_xshift_next
shl ra_xshift_next, r0, 3
add r0, r0, r3
and rb_x_next, r0, ~3
mov ra_y_next, r1
add ra_frame_base_next, rb_x_next, r2

# set up VPM write
# get width,height of block
mov vw_setup, rb28    ; mov r0, unif
shr r1, r0, i_shift16 # Extract width
sub rb29, rb24, r1 # Compute vdw_setup1(dst_pitch-width)
and r0, r0, rb_k255 # Extract height
add rb17, r0, 1
add rb18, r0, 3
shl r0, r0, 7
add r0, r0, r1 # Combine width and height of destination area
shl r0, r0, i_shift16 # Shift into bits 16 upwards of the vdw_setup0 register
add rb26, r0, rb27

# get filter coefficients

mov r0, unif          ; mov r3, 0
asr ra3, r0, rb23;      mul24 r0, r0, ra_k256
asr ra2, r0, rb23;      mul24 r0, r0, ra_k256
asr ra1, r0, rb23;      mul24 r0, r0, ra_k256
asr ra0, r0, rb23;      mov r0, unif
asr rb11, r0, rb23;     mul24 r0, r0, ra_k256
asr rb10, r0, rb23;     mul24 r0, r0, ra_k256
asr rb9, r0, rb23;      mul24 r0, r0, ra_k256
asr rb8, r0, rb23

mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

mov r0,      unif # U offset/weight
mov.ifnz r0, unif # V offset/weight

asr r1, r0, i_shift16 ; mul24 r0, r0, ra4  # a4 = 0x10000
shl r1, r1, rb13
asr rb12, r1, 1
asr rb14, r0, 15  # rb14 = weight*2

# rb14 - weight L0 * 2
# rb13 = weight denom + 6 + 9
# rb12 = (((is P) ? offset L0 * 2 : offset L1 + offset L0) + 1) << (rb13 - 1)

# r2 is elem_num
# r3 is loop counter
# retrieve texture results and pick out bytes
# then submit two more texture requests

# r3 = 0
:uvloop
# retrieve texture results and pick out bytes
# then submit two more texture requests

sub.setf -, r3, rb17      ; v8adds r3, r3, ra20                     ; ldtmu0     # loop counter increment
shr r0, r4, ra_xshift     ; mov.ifz ra_x, rb_x_next       ; ldtmu1
mov.ifz ra_frame_base, ra_frame_base_next ; mov rb31, r3
mov.ifz ra_y, ra_y_next   ; mov r3, rb_pitch
shr r1, r4, ra_xshift    ; v8subs r0, r0, rb20  # v8subs masks out all but bottom byte

max r2, ra_y, 0  # y
min r2, r2, rb_frame_height_minus_1
add ra_y, ra_y, 1         ; mul24 r2, r2, r3
add t0s, ra_x, r2    ; v8subs r1, r1, rb20
add t1s, ra_frame_base, r2

# generate seven shifted versions
# interleave with scroll of vertical context

mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

# apply horizontal filter
nop                  ; mul24 r2, r0, ra0
nop                  ; mul24.ifnz r2, ra0 << 8, r1 << 8
nop                  ; mul24      r3, ra1 << 1, r0 << 1
nop                  ; mul24.ifnz r3, ra1 << 9, r1 << 9
add r2, r2, r3       ; mul24    r3, ra2 << 2, r0 << 2
nop                  ; mul24.ifnz r3, ra2 << 10, r1 << 10
add r2, r2, r3       ; mul24    r3, ra3 << 3, r0 << 3
nop                  ; mul24.ifnz r3, ra3 << 11, r1 << 11
add r0, r2, r3       ; mov r3, rb31
sub.setf -, r3, 4    ; mov ra12, ra13
brr.anyn -, r:uvloop
mov ra13, ra14       # Delay slot 1
mov ra14, ra15       # Delay slot 2
mov ra15, r0         # Delay slot 3

# apply vertical filter and write to VPM

nop                     ; mul24 r1, ra14, rb10
nop                     ; mul24 r0, ra13, rb9
add r1, r1, r0          ; mul24 r0, ra12, rb8
add r1, r1, r0          ; mul24 r0, ra15, rb11
add r1, r1, r0          ; mov -, vw_wait
sub.setf -, r3, rb18    ; mul24 r1, r1, ra_k256
asr r1, r1, 14
nop                     ; mul24 r1, r1, rb14
shl r1, r1, 8

add r1, r1, rb12
brr.anyn -, r:uvloop
asr r1, r1, rb13
min r1, r1, rb_k255       # Delay 2
max vpm, r1, 0         # Delay 3

# DMA out for U

mov vw_setup, rb26 # VDW setup 0
mov vw_setup, rb29 # Stride
mov vw_addr, unif # start the VDW

# DMA out for V
# We need to wait for the U to complete first, but have nothing useful to compute while we wait.
# Could potentially push this write into the start of the next pipeline stage.
mov r0, 16
mov -, vw_wait

bra -, ra31
add vw_setup, rb26, r0 # VDW setup 0
mov vw_setup, rb29 # Stride
mov vw_addr, unif # start the VDW


################################################################################

# mc_filter_uv_b0(next_kernel, x, y, frame_u_base, frame_v_base, height, hcoeffs[0], hcoeffs[1], vcoeffs[0], vcoeffs[1], this_u_dst, this_v_dst)

# At this point we have already issued two pairs of texture requests for the current block
# ra_x, ra_x16_base point to the current coordinates for this block
::mc_filter_uv_b0
mov ra31, unif

# per-channel shifts were calculated on the *previous* invocation

# get base addresses and per-channel shifts for *next* invocation
add r0, unif, elem_num       # x
max r0, r0, 0                ; mov r1, unif # y
min r0, r0, rb_frame_width_minus_1 ; mov r3, unif # frame_base
sub r2, unif, r3             ; mov ra_xshift, ra_xshift_next # compute offset from frame base u to frame base v ;
shl ra_xshift_next, r0, 3
add r0, r0, r3
and rb_x_next, r0, ~3
mov ra_y_next, r1
add ra_frame_base_next, rb_x_next, r2

# set up VPM write, we need to save 16bit precision
# get width,height of block
mov vw_setup, rb21           ; mov r0, unif
shr r1, r0, i_shift16 # Extract width
sub rb29, rb24, r1 # Compute vdw_setup1(dst_pitch-width)
and r0, r0, rb_k255 # Extract height
add rb17, r0, 1
add rb18, r0, 3
shl r0, r0, 7
add r0, r0, r1 # Combine width and height of destination area
shl r0, r0, i_shift16 # Shift into bits 16 upwards of the vdw_setup0 register
add rb26, r0, rb27

# get filter coefficients

mov r0, unif          ; mov r3, 0
asr ra3, r0, rb23;      mul24 r0, r0, ra_k256
asr ra2, r0, rb23;      mul24 r0, r0, ra_k256
asr ra1, r0, rb23;      mul24 r0, r0, ra_k256
asr ra0, r0, rb23;      mov r0, unif
asr rb11, r0, rb23;     mul24 r0, r0, ra_k256
asr rb10, r0, rb23;     mul24 r0, r0, ra_k256
asr rb9, r0, rb23;      mul24 r0, r0, ra_k256
asr rb8, r0, rb23

# r2 is elem_num
# r3 is loop counter

mov r5rep, -8
mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

mov      rb14, unif   # U weight L0
mov.ifnz rb14, unif   # V weight L0
# rb14 unused in b0 but will hang around till the second pass

# retrieve texture results and pick out bytes
# then submit two more texture requests

# r3 = 0
:uvloop_b0
# retrieve texture results and pick out bytes
# then submit two more texture requests

sub.setf -, r3, rb17      ; v8adds r3, r3, ra20                     ; ldtmu0     # loop counter increment
shr r0, r4, ra_xshift     ; mov.ifz ra_x, rb_x_next       ; ldtmu1
mov.ifz ra_frame_base, ra_frame_base_next ; mov rb31, r3
mov.ifz ra_y, ra_y_next   ; mov r3, rb_pitch
shr r1, r4, ra_xshift    ; v8subs r0, r0, rb20  # v8subs masks out all but bottom byte

max r2, ra_y, 0  # y
min r2, r2, rb_frame_height_minus_1
add ra_y, ra_y, 1         ; mul24 r2, r2, r3
add t0s, ra_x, r2    ; v8subs r1, r1, rb20
add t1s, ra_frame_base, r2

# generate seven shifted versions
# interleave with scroll of vertical context

mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

nop                  ; mul24 r2, r0, ra0
nop                  ; mul24.ifnz r2, ra0 << 8, r1 << 8
nop                  ; mul24      r3, ra1 << 1, r0 << 1
nop                  ; mul24.ifnz r3, ra1 << 9, r1 << 9
add r2, r2, r3       ; mul24    r3, ra2 << 2, r0 << 2
nop                  ; mul24.ifnz r3, ra2 << 10, r1 << 10
add r2, r2, r3       ; mul24    r3, ra3 << 3, r0 << 3
nop                  ; mul24.ifnz r3, ra3 << 11, r1 << 11
add r0, r2, r3       ; mov r3, rb31
sub.setf -, r3, 4    ; mov ra12, ra13
brr.anyn -, r:uvloop_b0
mov ra13, ra14       # Delay slot 1
mov ra14, ra15       # Delay slot 2
mov ra15, r0         # Delay slot 3

# apply vertical filter and write to VPM

nop                     ; mul24 r1, ra14, rb10
nop                     ; mul24 r0, ra13, rb9
add r1, r1, r0          ; mul24 r0, ra12, rb8
add r1, r1, r0          ; mul24 r0, ra15, rb11
add r1, r1, r0          ; mov -, vw_wait
sub.setf -, r3, rb18
brr.anyn -, r:uvloop_b0
asr vpm, r1, 6         # Delay 1 shifts down by shift2=6, but results are still in 16bit precision
nop                    # Delay 2
nop                    # Delay 3

# in pass0 we don't really need to save any results, but need to discard the uniforms
# DMA out for U

bra -, ra31
mov r0, unif           # Delay 1
mov r0, unif           # Delay 2
nop                    # Delay 3


################################################################################

::mc_filter_uv_b
mov ra31, unif

# per-channel shifts were calculated on the *previous* invocation

mov ra_xshift, ra_xshift_next

# get base addresses and per-channel shifts for *next* invocation
add r0, unif, elem_num    # x
max r0, r0, 0; mov r1, unif # y
min r0, r0, rb_frame_width_minus_1 ; mov r3, unif # frame_base
shl ra_xshift_next, r0, 3
sub r2, unif, r3 # compute offset from frame base u to frame base v
add r0, r0, r3
and rb_x_next, r0, ~3
mov ra_y_next, r1
add ra_frame_base_next, rb_x_next, r2

# set up VPM write
mov vw_setup, rb28

# get width,height of block
mov r0, unif
shr r1, r0, i_shift16 # Extract width
sub rb29, rb24, r1 # Compute vdw_setup1(dst_pitch-width)
and r0, r0, rb_k255 # Extract height
add rb17, r0, 1
add rb18, r0, 3
shl r0, r0, 7

# r0 is currently height<<7
# For vr_setup we want height<<20 (so 20-7=13 additional bits)
shl r3, r0, 13
shl r3, r3, 8 # Mask off top 8 bits
shr r3, r3, 8

add r0, r0, r1 # Combine width and height of destination area
shl r0, r0, i_shift16 # Shift into bits 16 upwards of the vdw_setup0 register
add rb26, r0, rb27

# In a B frame, so also set up VPM read (reading back 16bit precision)
add vr_setup, r3, rb21

# get filter coefficients

mov r0, unif          ; mov r3, 0               # r3 = 0 for loop counting later
asr ra3, r0, rb23;      mul24 r0, r0, ra_k256
asr ra2, r0, rb23;      mul24 r0, r0, ra_k256
asr ra1, r0, rb23;      mul24 r0, r0, ra_k256
asr ra0, r0, rb23;      mov r0, unif
asr rb11, r0, rb23;     mul24 r0, r0, ra_k256
asr rb10, r0, rb23;     mul24 r0, r0, ra_k256
asr rb9, r0, rb23;      mul24 r0, r0, ra_k256
asr rb8, r0, rb23

mov r5rep, -8
mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

# Get offset & weight stuff

mov      r0, unif         # U offset/weight
# The unif read occurs unconditionally, only the write is conditional
mov.ifnz r0, unif         # V offset/weight

asr r1, r0, i_shift16
shl r1, r1, rb13
asr rb12, r1, 1           ; mul24 r0, r0, ra4  # ra4 = 0x10000
asr ra18, r0, i_shift16

# retrieve texture results and pick out bytes
# then submit two more texture requests

# r3 = 0
:uvloop_b
# retrieve texture results and pick out bytes
# then submit two more texture requests

sub.setf -, r3, rb17      ; v8adds r3, r3, ra20           ; ldtmu0     # loop counter increment
shr r0, r4, ra_xshift     ; mov.ifz ra_x, rb_x_next       ; ldtmu1
mov.ifz ra_frame_base, ra_frame_base_next ; mov rb31, r3
mov.ifz ra_y, ra_y_next   ; mov r3, rb_pitch
shr r1, r4, ra_xshift     ; v8subs r0, r0, rb20  # v8subs masks out all but bottom byte

max r2, ra_y, 0  # y
min r2, r2, rb_frame_height_minus_1
add ra_y, ra_y, 1         ; mul24 r2, r2, r3
add t0s, ra_x, r2         ; v8subs r1, r1, rb20
add t1s, ra_frame_base, r2

# generate seven shifted versions
# interleave with scroll of vertical context

mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

nop                  ; mul24 r2, r0, ra0
nop                  ; mul24.ifnz r2, ra0 << 8, r1 << 8
nop                  ; mul24      r3, ra1 << 1, r0 << 1
nop                  ; mul24.ifnz r3, ra1 << 9, r1 << 9
add r2, r2, r3       ; mul24    r3, ra2 << 2, r0 << 2
nop                  ; mul24.ifnz r3, ra2 << 10, r1 << 10
add r2, r2, r3       ; mul24    r3, ra3 << 3, r0 << 3
nop                  ; mul24.ifnz r3, ra3 << 11, r1 << 11
add r0, r2, r3       ; mov r3, rb31
sub.setf -, r3, 4    ; mov ra12, ra13
brr.anyn -, r:uvloop_b
mov ra13, ra14       # Delay slot 1
mov ra14, ra15       # Delay slot 2
mov ra15, r0         # Delay slot 3

# apply vertical filter and write to VPM

nop                     ; mul24 r1, ra14, rb10
nop                     ; mul24 r0, ra13, rb9
add r1, r1, r0          ; mul24 r0, ra12, rb8
add r1, r1, r0          ; mul24 r0, ra15, rb11
# Beware: vpm read gets unsigned 16-bit value, so we must sign extend it
add r1, r1, r0          ; mul24 r0, vpm, ra4  # ra4 = 0x10000
sub.setf -, r3, rb18    ; mul24 r1, r1, ra_k256
asr r1, r1, 14          # shift2=6

asr r0, r0, i_shift16   ; mul24 r1, r1, ra18
nop                     ; mul24 r0, r0, rb14

add r0, r0, r1          ; mov -, vw_wait
shl r0, r0, 8           # Lose bad top 8 bits & sign extend

add r1, r0, rb12        # rb12 = (offsetL0 + offsetL1 + 1) << (rb13 - 1)

brr.anyn -, r:uvloop_b
asr r1, r1, rb13         # Delay 1
min r1, r1, rb_k255       # Delay 2
max vpm, r1, 0         # Delay 3


# DMA out for U

mov vw_setup, rb26 # VDW setup 0
mov vw_setup, rb29 # Stride
mov vw_addr, unif # start the VDW

# DMA out for V
# We need to wait for the U to complete first, but have nothing useful to compute while we wait.
# Could potentially push this write into the start of the next pipeline stage.
mov r0, 16
mov -, vw_wait

bra -, ra31
add vw_setup, rb26, r0 # VDW setup 0
mov vw_setup, rb29 # Stride
mov vw_addr, unif # start the VDW

################################################################################

# mc_exit()

::mc_exit
mov  -, vw_wait # wait on the VDW

mov -,srel(0)

ldtmu0
ldtmu1
ldtmu0
ldtmu1

nop        ; nop ; thrend
nop        ; nop # delay slot 1
nop        ; nop # delay slot 2

# mc_interrupt_exit8()
::mc_interrupt_exit8
mov  -, vw_wait # wait on the VDW

ldtmu0
ldtmu1
ldtmu0
ldtmu1

mov -,sacq(0) # 1
mov -,sacq(0) # 2
mov -,sacq(0) # 3
mov -,sacq(0) # 4
mov -,sacq(0) # 5
mov -,sacq(0) # 6
mov -,sacq(0) # 7

nop        ; nop ; thrend
mov interrupt, 1; nop # delay slot 1
nop        ; nop # delay slot 2





# LUMA CODE

# The idea is to form B predictions by doing 8 pixels from ref0 in parallel with 8 pixels from ref1.
# For P frames we make the second x,y coordinates offset by +8

################################################################################
# mc_setup(y_x, ref_y_base, y2_x2, ref_y2_base, frame_width_height, pitch, dst_pitch, offset_shift, tbd, next_kernel)
::mc_setup
  mov r3, 16

  # Need to save these because we need to know the frame dimensions before computing texture coordinates
  mov ra8, unif
  mov ra9, unif
  mov ra10, unif
  mov ra11, unif

# Read image dimensions
  mov r1, unif # width_height
  shl r0,r1,r3
  asr r1,r1,r3 # width
  asr r0,r0,r3 # height
  sub rb_frame_width_minus_1,r1,1
  sub rb_frame_height_minus_1,r0,1

# get source pitch
  mov rb_pitch, unif

# get destination pitch
  mov r0, unif
  mov r1, vdw_setup_1(0)
  add rb24, r1, r0

# Compute base address for first and second access
  mov r1, ra8 # y_x
  shl r0,r1,r3 # r0 is x<<16
  asr r1,r1,r3 # r1 is y
  asr r0,r0,r3 # r0 is x
  add r0, r0, elem_num # Load x
  max r0, r0, 0
  min r0, r0, rb_frame_width_minus_1 ; mov r2, ra9  # Load the frame base
  shl ra_xshift_next, r0, 3 # Compute shifts
  add ra_y, r1, 1
  and r0, r0, ~3  # r0 gives the clipped and aligned x coordinate
  add r2, r2, r0  # r2 is address for frame0 (not including y offset)
  max r1, r1, 0
  min r1, r1, rb_frame_height_minus_1
  nop             ; mul24 r1, r1, rb_pitch   # r2 contains the addresses (not including y offset) for frame0
  add t0s, r2, r1 ; mov ra_frame_base, r2

  mov r1, ra10 # y_x
  shl r0,r1,r3 # r0 is x<<16
  asr r1,r1,r3 # r1 is y
  asr r0,r0,r3 # r0 is x
  add r0, r0, elem_num # Load x
  max r0, r0, 0
  min r0, r0, rb_frame_width_minus_1 ; mov r2, ra11  # Load the frame base
  shl rx_xshift2_next, r0, 3 # Compute shifts
  add ra_y2, r1, 1
  and r0, r0, ~3  # r0 gives the clipped and aligned x coordinate
  add r2, r2, r0  # r2 is address for frame1 (not including y offset)
  max r1, r1, 0
  min r1, r1, rb_frame_height_minus_1
  nop             ; mul24 r1, r1, rb_pitch   # r2 contains the addresses (not including y offset) for frame0
  add t1s, r2, r1 ; mov ra_frame_base2, r2


# load constants

  mov ra20, 1
  mov ra_k256, 256
  mov ra30, 64

  mov rb20, 0xffffff00
  mov rb_k255, 255
  mov rb23, 24

# touch vertical context to keep simulator happy

  mov ra8, 0
  mov ra9, 0
  mov ra10, 0
  mov ra11, 0
  mov ra12, 0
  mov ra13, 0
  mov ra14, 0
  mov ra15, 0

# Compute part of VPM to use
  mov r2, qpu_num
  mov r1, r2
  asr r1, r1, 2
  shl r1, r1, 6
  mov r0, r2
  and r0, r0, 3
  add r0, r0, r1
  mov r1, vpm_setup(0, 4, h8p(0, 0))   # 4 is stride - stride acts on ADDR which is Y[5:0],B[1:0] for 8 bit
  add rb28, r0, r1  # VPM for saving data
  mov r1, vdw_setup_0(0, 0, dma_h8p(0,0,0)) # height,width added later
  shl r0, r0, 5
  add rb27, r0, r1  # Command for dma output

# Weighted prediction denom
  add rb13, unif, 9  # unif = weight denom + 6

  mov -, unif # Unused

# submit texture requests for second line
  max r1, ra_y, 0
  min r1, r1, rb_frame_height_minus_1
  add ra_y, ra_y, 1
  nop ; mul24 r1, r1, rb_pitch
  add t0s, r1, ra_frame_base

  max r1, ra_y2, 0
  min r1, r1, rb_frame_height_minus_1
  add ra_y2, ra_y2, 1
  nop ; mul24 r1, r1, rb_pitch
  add t1s, r1, ra_frame_base2

# FALL THROUGHT TO PER-BLOCK SETUP

# Start of per-block setup code
# P and B blocks share the same setup code to save on Icache space
:per_block_setup
  mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]
  mov ra31, unif

# per-channel shifts were calculated on the *previous* invocation
  mov ra_xshift, ra_xshift_next
  mov rx_xshift2, rx_xshift2_next

# get base addresses and per-channel shifts for *next* invocation
  mov r3, 16
  mov r1, unif # y_x
  shl r0,r1,r3 # r0 is x<<16
  asr r1,r1,r3 # r1 is y
  asr r0,r0,r3 # r0 is x
  add r0, r0, elem_num # Load x
  max r0, r0, 0
  min r0, r0, rb_frame_width_minus_1 ; mov r2, unif  # Load the frame base
  shl ra_xshift_next, r0, 3 # Compute shifts
  mov ra_y_next, r1
  and r0, r0, ~3  # r0 gives the clipped and aligned x coordinate
  add ra_frame_base_next, r2, r0 ; mov r1, unif # y2_x2

  shl r0,r1,r3 # r0 is x2<<16
  asr r1,r1,r3 # r1 is y2
  asr r0,r0,r3 # r0 is x2
  add r0, r0, elem_num # Load x
  max r0, r0, 0
  min r0, r0, rb_frame_width_minus_1 ; mov r2, unif  # Load the frame base
  shl rx_xshift2_next, r0, 3 # Compute shifts
  mov ra_y2_next, r1
  and r0, r0, ~3  # r0 gives the clipped and aligned x coordinate
  add rx_frame_base2_next, r2, r0  # r2 is address for frame1 (not including y offset)

# set up VPM write
  mov vw_setup, rb28

# get width,height of block
  mov r0, unif
  shr r1, r0, r3 # Extract width
  sub rb29, rb24, r1 # Compute vdw_setup1(dst_pitch-width)
  and r0, r0, rb_k255 # Extract height
  add rb17, r0, 5
  add rb18, r0, 7
  shl r0, r0, 7
  add r0, r0, r1 # Combine width and height of destination area
  shl r0, r0, r3 # Shift into bits 16 upwards of the vdw_setup0 register
  add rb26, r0, rb27

# get filter coefficients and discard unused B frame values
  mov r0, unif ; mov r1,1  # Packed filter offsets, unpack into ra8... (to be used for vertical context later)
  asr ra9, r0, rb23;      mul24 r0, r0, ra_k256 # my2
  asr ra8, r0, rb23;      mul24 r0, r0, ra_k256 # mx2
  asr.ifz ra9, r0, rb23;  mul24 r0, r0, ra_k256 # my:my2
  asr.ifz ra8, r0, rb23                      # mx:mx2
  sub ra9,3,ra9
  sub ra8,3,ra8
  shl ra9,ra9,3   # Scale up by 8
  shl ra8,ra8,3   # Scale up by 8
# Now if we want aligned we have a mul of 1, so put 0 coefficients at the top
  mov r1,0xffff00
  shl r0, r1, ra8
  asr ra0, r0, rb23
  shl r0, r1, ra9
  asr rb4, r0, rb23

  mov r1,0x1040400
  shl r0, r1, ra8
  asr ra1, r0, rb23
  shl r0, r1, ra9
  asr rb5, r0, rb23

  mov r1,0xfbf5f600
  shl r0, r1, ra8
  asr ra2, r0, rb23
  shl r0, r1, ra9
  asr rb6, r0, rb23

  mov r1,0x11283a40
  shl r0, r1, ra8
  asr ra3, r0, rb23
  shl r0, r1, ra9
  asr rb7, r0, rb23

  mov r1,0x3a281100
  shl r0, r1, ra8
  asr ra4, r0, rb23
  shl r0, r1, ra9
  asr rb8, r0, rb23

  mov r1,0xf6f5fb00
  shl r0, r1, ra8
  asr ra5, r0, rb23
  shl r0, r1, ra9
  asr rb9, r0, rb23

  mov r1,0x4040100
  shl r0, r1, ra8
  asr ra6, r0, rb23
  shl r0, r1, ra9
  asr rb10, r0, rb23

  mov r1,0xffff0000
  shl r0, r1, ra8
  asr ra7, r0, rb23
  shl r0, r1, ra9
  asr rb11, r0, rb23

# Extract weighted prediction information
# r3 = 16
# rb13 = weight denom + 6 + 8

  mov r0, unif      # weight L1 (hi16)/weight L0 (lo16)  TODO move up
  shl r1, unif, rb13 # combined offet = ((is P) ? offset L0 * 2 : offset L1 + offset L0) + 1)
  asr ra18, r0, r3
  bra -, ra31
  shl r0, r0, r3
  asr rb14, r0, r3 ; mov r3, 0
  asr rb12, r1, 1
# >>> branch ra31
#
# r3 = 0
# ra18 = weight L1
# rb14 - weight L0
# rb13 = weight denom + 6 + 8
# rb12 = (((is P) ? offset L0 * 2 : offset L1 + offset L0) + 1) << (rb13 - 1)


################################################################################
# mc_filter(y_x, frame_base, y2_x2, frame_base2, width_height, my2_mx2_my_mx, offsetweight0, this_dst, next_kernel)
# In a P block, y2_x2 should be y_x+8
# At this point we have already issued two pairs of texture requests for the current block

::mc_filter
  add rb14, rb14, rb14

# r3 = 0

:yloop
# retrieve texture results and pick out bytes
# then submit two more texture requests

# If we knew there was no clipping then this code would get simpler.
# Perhaps we could add on the pitch and clip using larger values?

  sub.setf -, r3, rb17      ; v8adds r3, r3, ra20                            ; ldtmu0
  shr r0, r4, ra_xshift     ; mov.ifz ra_frame_base2, rx_frame_base2_next    ; ldtmu1
  mov.ifz ra_frame_base, ra_frame_base_next ; mov rb31, r3
  mov.ifz ra_y, ra_y_next   ; mov r3, rb_pitch
  shr r1, r4, rx_xshift2
  mov.ifz ra_y2, ra_y2_next

  max r2, ra_y, 0  # y
  min r2, r2, rb_frame_height_minus_1
  add ra_y, ra_y, 1            ; mul24 r2, r2, r3
  add t0s, ra_frame_base, r2   ; v8subs r0, r0, rb20 # v8subs masks out all but bottom byte

  max r2, ra_y2, 0  # y
  min r2, r2, rb_frame_height_minus_1
  add ra_y2, ra_y2, 1            ; mul24 r2, r2, r3
  add t1s, ra_frame_base2, r2   ; v8subs r1, r1, rb20

# generate seven shifted versions
# interleave with scroll of vertical context

  mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

# apply horizontal filter
  nop                  ; mul24 r2, r0, ra0
  nop                  ; mul24.ifnz r2, ra0 << 8, r1 << 8
  nop                  ; mul24      r3, ra1 << 1, r0 << 1
  nop                  ; mul24.ifnz r3, ra1 << 9, r1 << 9
  add r2, r2, r3       ; mul24    r3, ra2 << 2, r0 << 2
  nop                  ; mul24.ifnz r3, ra2 << 10, r1 << 10
  add r2, r2, r3       ; mul24    r3, ra3 << 3, r0 << 3
  nop                  ; mul24.ifnz r3, ra3 << 11, r1 << 11
  add r2, r2, r3       ; mul24    r3, ra4 << 4, r0 << 4
  nop                  ; mul24.ifnz r3, ra4 << 12, r1 << 12
  add r2, r2, r3       ; mul24    r3, ra5 << 5, r0 << 5
  nop                  ; mul24.ifnz r3, ra5 << 13, r1 << 13
  add r2, r2, r3       ; mul24    r3, ra6 << 6, r0 << 6
  nop                  ; mul24.ifnz r3, ra6 << 14, r1 << 14
  add r2, r2, r3       ; mul24    r3, ra7 << 7, r0 << 7
  nop                  ; mul24.ifnz r3, ra7 << 15, r1 << 15
  add r0, r2, r3       ; mov r3, rb31
  sub.setf -, r3, 8    ; mov ra8, ra9
  mov ra9, ra10
  mov ra10, ra11
  mov ra11, ra12
  mov ra12, ra13
  brr.anyn -, r:yloop
  mov ra13, ra14       # Delay slot 1
  mov ra14, ra15       # Delay slot 2
  mov ra15, r0         # Delay slot 3

# apply vertical filter and write to VPM

  nop                     ; mul24 r1, ra14, rb10
  nop                     ; mul24 r0, ra13, rb9
  add r1, r1, r0          ; mul24 r0, ra12, rb8
  add r1, r1, r0          ; mul24 r0, ra15, rb11
  add r1, r1, r0          ; mul24 r0, ra8, rb4
  add r1, r1, r0          ; mul24 r0, ra9, rb5
  add r1, r1, r0          ; mul24 r0, ra10, rb6
  add r1, r1, r0          ; mul24 r0, ra11, rb7

  add r1, r1, r0          ; mov -, vw_wait
# At this point r1 is a 22-bit signed quantity: 8 (original sample),
#  +6, +6 (each pass), +1 (the passes can overflow slightly), +1 (sign)
# The top 8 bits have rubbish in them as mul24 is unsigned
# The low 6 bits need discard before weighting
  sub.setf -, r3, rb18    ; mul24 r1, r1, ra_k256  # x256 - sign extend & discard rubbish
  asr r1, r1, 14
  nop                     ; mul24 r1, r1, rb14
  shl r1, r1, 8

  add r1, r1, rb12
  brr.anyn -, r:yloop
  asr r1, r1, rb13
# We have a saturating pack unit - I can't help feeling it should be useful here
  min r1, r1, rb_k255       # Delay 2  rb_k255 = 255
  max vpm, r1, 0         # Delay 3
# >>> branch.anyn yloop

# DMA out

  brr -, r:per_block_setup
  mov vw_setup, rb26 # VDW setup 0    Delay 1
  mov vw_setup, rb29 # Stride         Delay 2
  mov vw_addr, unif # start the VDW   Delay 3



################################################################################

# mc_filter_b(y_x, frame_base, y2_x2, frame_base2, width_height, my2_mx2_my_mx, offsetweight0, this_dst, next_kernel)
# In a P block, only the first half of coefficients contain used information.
# At this point we have already issued two pairs of texture requests for the current block
# May be better to just send 16.16 motion vector and figure out the coefficients inside this block (only 4 cases so can compute hcoeffs in around 24 cycles?)
# Can fill in the coefficients so only
# Can also assume default weighted prediction for B frames.
# Perhaps can unpack coefficients in a more efficient manner by doing H/V for a and b at the same time?
# Or possibly by taking advantage of symmetry?
# From 19->7 32bits per command.
::mc_filter_b

:yloopb
# retrieve texture results and pick out bytes
# then submit two more texture requests

# If we knew there was no clipping then this code would get simpler.
# Perhaps we could add on the pitch and clip using larger values?

  sub.setf -, r3, rb17      ; v8adds r3, r3, ra20                            ; ldtmu0
  shr r0, r4, ra_xshift     ; mov.ifz ra_frame_base2, rx_frame_base2_next    ; ldtmu1
  mov.ifz ra_frame_base, ra_frame_base_next ; mov rb31, r3
  mov.ifz ra_y, ra_y_next   ; mov r3, rb_pitch
  shr r1, r4, rx_xshift2
  mov.ifz ra_y2, ra_y2_next

  max r2, ra_y, 0  # y
  min r2, r2, rb_frame_height_minus_1
  add ra_y, ra_y, 1            ; mul24 r2, r2, r3
  add t0s, ra_frame_base, r2   ; v8subs r0, r0, rb20 # v8subs masks out all but bottom byte

  max r2, ra_y2, 0  # y
  min r2, r2, rb_frame_height_minus_1
  add ra_y2, ra_y2, 1            ; mul24 r2, r2, r3
  add t1s, ra_frame_base2, r2   ; v8subs r1, r1, rb20

# generate seven shifted versions
# interleave with scroll of vertical context

  mov.setf -, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

# apply horizontal filter
  nop                  ; mul24 r2, r0, ra0
  nop                  ; mul24.ifnz r2, ra0 << 8, r1 << 8
  nop                  ; mul24      r3, ra1 << 1, r0 << 1
  nop                  ; mul24.ifnz r3, ra1 << 9, r1 << 9
  add r2, r2, r3       ; mul24    r3, ra2 << 2, r0 << 2
  nop                  ; mul24.ifnz r3, ra2 << 10, r1 << 10
  add r2, r2, r3       ; mul24    r3, ra3 << 3, r0 << 3
  nop                  ; mul24.ifnz r3, ra3 << 11, r1 << 11
  add r2, r2, r3       ; mul24    r3, ra4 << 4, r0 << 4
  nop                  ; mul24.ifnz r3, ra4 << 12, r1 << 12
  add r2, r2, r3       ; mul24    r3, ra5 << 5, r0 << 5
  nop                  ; mul24.ifnz r3, ra5 << 13, r1 << 13
  add r2, r2, r3       ; mul24    r3, ra6 << 6, r0 << 6
  nop                  ; mul24.ifnz r3, ra6 << 14, r1 << 14
  add r2, r2, r3       ; mul24    r3, ra7 << 7, r0 << 7
  nop                  ; mul24.ifnz r3, ra7 << 15, r1 << 15
  add r0, r2, r3       ; mov r3, rb31
  sub.setf -, r3, 8    ; mov ra8, ra9
  mov ra9, ra10
  mov ra10, ra11
  mov ra11, ra12
  mov ra12, ra13
  brr.anyn -, r:yloopb
  mov ra13, ra14       # Delay slot 1
  mov ra14, ra15       # Delay slot 2
  mov ra15, r0         # Delay slot 3

  # apply vertical filter and write to VPM

  nop                     ; mul24 r1, ra14, rb10
  nop                     ; mul24 r0, ra13, rb9
  add r1, r1, r0          ; mul24 r0, ra12, rb8
  add r1, r1, r0          ; mul24 r0, ra15, rb11
  add r1, r1, r0          ; mul24 r0, ra8, rb4
  add r1, r1, r0          ; mul24 r0, ra9, rb5
  add r1, r1, r0          ; mul24 r0, ra10, rb6
  add r1, r1, r0          ; mul24 r0, ra11, rb7

  add r1, r1, r0          ; mov -, vw_wait
# As with P-pred r1 is a 22-bit signed quantity in 32-bits
# Top 8 bits are bad - low 6 bits should be discarded
  sub.setf -, r3, rb18    ; mul24 r1, r1, ra_k256

#  asr r0, r1, 14
#  asr r1, r1, 6           # Wait state so we can use the rotate instruction
#  nop                     ; mul24 r0, r0 << 8, ra_k256 << 8 # Rotate to align left and right halves

#  add r1, r1, ra_k0x4000
#  add r1, r1, r0
#  brr.anyn -, r:yloopb
#  asr r1, r1, 15         # Delay 1
#  min r1, r1, rb_k255       # Delay 2
#  max vpm, r1, 0         # Delay 3

  asr r1, r1, 14
  nop                     ; mul24 r0, r1, rb14
  nop                     ; mul24 r1, r1 << 8, ra18 << 8

  add r1, r1, r0
  shl r1, r1, 8

  add r1, r1, rb12

  brr.anyn -, r:yloopb
  asr r1, r1, rb13         # Delay 1
  min r1, r1, rb_k255       # Delay 2
  max vpm, r1, 0         # Delay 3

# DMA out
  brr -, r:per_block_setup
  mov vw_setup, rb26 # VDW setup 0    Delay 1
  mov vw_setup, rb29 # Stride         Delay 2
  mov vw_addr, unif # start the VDW   Delay 3

################################################################################

# mc_interrupt_exit12()
::mc_interrupt_exit12
  mov  -, vw_wait # wait on the VDW

  # Dummy wait to test instructions
#  mov r3,1000000
#:dummy_loop
#  sub.setf r3, r3, 1
#  nop
#  nop
#  brr.anynn -, r:dummy_loop
#  nop
#  nop
#  nop

  ldtmu0
  ldtmu0
  ldtmu1
  ldtmu1

  mov -,sacq(0) # 1
  mov -,sacq(0) # 2
  mov -,sacq(0) # 3
  mov -,sacq(0) # 4
  mov -,sacq(0) # 5
  mov -,sacq(0) # 6
  mov -,sacq(0) # 7
  mov -,sacq(0) # 8
  mov -,sacq(0) # 9
  mov -,sacq(0) # 10
  mov -,sacq(0) # 11

  nop        ; nop ; thrend
  mov interrupt, 1; nop # delay slot 1
  nop        ; nop # delay slot 2


::mc_exit1
  mov  -, vw_wait # wait on the VDW

  ldtmu0
  ldtmu1
  ldtmu0
  ldtmu1
  nop        ; nop ; thrend
  mov interrupt, 1; nop # delay slot 1
  nop        ; nop # delay slot 2


::mc_end
# Do not add code here because mc_end must appear after all other code.
