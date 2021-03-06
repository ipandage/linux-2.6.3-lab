/*
 *  PARISC TLB and cache flushing support
 *  Copyright (C) 2000-2001 Hewlett-Packard (John Marvin)
 *  Copyright (C) 2001 Matthew Wilcox (willy at parisc-linux.org)
 *  Copyright (C) 2002 Richard Hirst (rhirst with parisc-linux.org)
 *
 *    This program is free software; you can redistribute it and/or modify
 *    it under the terms of the GNU General Public License as published by
 *    the Free Software Foundation; either version 2, or (at your option)
 *    any later version.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with this program; if not, write to the Free Software
 *    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * NOTE: fdc,fic, and pdc instructions that use base register modification
 *       should only use index and base registers that are not shadowed,
 *       so that the fast path emulation in the non access miss handler
 *       can be used.
 */

#ifdef __LP64__
#define ADDIB   addib,*
#define CMPB    cmpb,*
#define ANDCM   andcm,*

	.level 2.0w
#else
#define ADDIB   addib,
#define CMPB    cmpb,
#define ANDCM   andcm

	.level 2.0
#endif

#include <asm/assembly.h>
#include <asm/psw.h>
#include <asm/pgtable.h>
#include <asm/cache.h>

	.text
	.align 128

	.export flush_tlb_all_local,code

flush_tlb_all_local:
	.proc
	.callinfo NO_CALLS
	.entry

	/*
	 * The pitlbe and pdtlbe instructions should only be used to
	 * flush the entire tlb. Also, there needs to be no intervening
	 * tlb operations, e.g. tlb misses, so the operation needs
	 * to happen in real mode with all interruptions disabled.
	 */

	/*
	 * Once again, we do the rfi dance ... some day we need examine
	 * all of our uses of this type of code and see what can be
	 * consolidated.
	 */

	rsm     PSW_SM_I,%r19      /* relied upon translation! */
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	
	rsm     PSW_SM_Q,%r0       /* Turn off Q bit to load iia queue */
	ldil    L%REAL_MODE_PSW, %r1
	ldo     R%REAL_MODE_PSW(%r1), %r1
	mtctl	%r1, %cr22
	mtctl	%r0, %cr17	/* Clear IIASQ tail */
	mtctl	%r0, %cr17	/* Clear IIASQ head */
	ldil    L%PA(1f),%r1
	ldo     R%PA(1f)(%r1),%r1
	mtctl	%r1, %cr18	/* IIAOQ head */
	ldo	4(%r1), %r1
	mtctl	%r1, %cr18	/* IIAOQ tail */
	rfi
	nop

1:      ldil            L%PA(cache_info),%r1
	ldo             R%PA(cache_info)(%r1),%r1

	/* Flush Instruction Tlb */

	LDREG           ITLB_SID_BASE(%r1),%r20
	LDREG           ITLB_SID_STRIDE(%r1),%r21
	LDREG           ITLB_SID_COUNT(%r1),%r22
	LDREG           ITLB_OFF_BASE(%r1),%arg0
	LDREG           ITLB_OFF_STRIDE(%r1),%arg1
	LDREG           ITLB_OFF_COUNT(%r1),%arg2
	LDREG           ITLB_LOOP(%r1),%arg3

	ADDIB=          -1,%arg3,fitoneloop     /* Preadjust and test */
	movb,<,n        %arg3,%r31,fitdone      /* If loop < 0, skip */
	copy            %arg0,%r28              /* Init base addr */

fitmanyloop:                                    /* Loop if LOOP >= 2 */
	mtsp            %r20,%sr1
	add             %r21,%r20,%r20          /* increment space */
	copy            %arg2,%r29              /* Init middle loop count */

fitmanymiddle:                                  /* Loop if LOOP >= 2 */
	ADDIB>          -1,%r31,fitmanymiddle   /* Adjusted inner loop decr */
	pitlbe          0(%sr1,%r28)
	pitlbe,m        %arg1(%sr1,%r28)        /* Last pitlbe and addr adjust */
	ADDIB>          -1,%r29,fitmanymiddle   /* Middle loop decr */
	copy            %arg3,%r31              /* Re-init inner loop count */

	movb,tr         %arg0,%r28,fitmanyloop  /* Re-init base addr */
	ADDIB<=,n       -1,%r22,fitdone         /* Outer loop count decr */

fitoneloop:                                     /* Loop if LOOP = 1 */
	mtsp            %r20,%sr1
	copy            %arg0,%r28              /* init base addr */
	copy            %arg2,%r29              /* init middle loop count */

fitonemiddle:                                   /* Loop if LOOP = 1 */
	ADDIB>          -1,%r29,fitonemiddle    /* Middle loop count decr */
	pitlbe,m        %arg1(%sr1,%r28)        /* pitlbe for one loop */

	ADDIB>          -1,%r22,fitoneloop      /* Outer loop count decr */
	add             %r21,%r20,%r20          /* increment space */

fitdone:

	/* Flush Data Tlb */

	LDREG           DTLB_SID_BASE(%r1),%r20
	LDREG           DTLB_SID_STRIDE(%r1),%r21
	LDREG           DTLB_SID_COUNT(%r1),%r22
	LDREG           DTLB_OFF_BASE(%r1),%arg0
	LDREG           DTLB_OFF_STRIDE(%r1),%arg1
	LDREG           DTLB_OFF_COUNT(%r1),%arg2
	LDREG           DTLB_LOOP(%r1),%arg3

	ADDIB=          -1,%arg3,fdtoneloop     /* Preadjust and test */
	movb,<,n        %arg3,%r31,fdtdone      /* If loop < 0, skip */
	copy            %arg0,%r28              /* Init base addr */

fdtmanyloop:                                    /* Loop if LOOP >= 2 */
	mtsp            %r20,%sr1
	add             %r21,%r20,%r20          /* increment space */
	copy            %arg2,%r29              /* Init middle loop count */

fdtmanymiddle:                                  /* Loop if LOOP >= 2 */
	ADDIB>          -1,%r31,fdtmanymiddle   /* Adjusted inner loop decr */
	pdtlbe          0(%sr1,%r28)
	pdtlbe,m        %arg1(%sr1,%r28)        /* Last pdtlbe and addr adjust */
	ADDIB>          -1,%r29,fdtmanymiddle   /* Middle loop decr */
	copy            %arg3,%r31              /* Re-init inner loop count */

	movb,tr         %arg0,%r28,fdtmanyloop  /* Re-init base addr */
	ADDIB<=,n       -1,%r22,fdtdone         /* Outer loop count decr */

fdtoneloop:                                     /* Loop if LOOP = 1 */
	mtsp            %r20,%sr1
	copy            %arg0,%r28              /* init base addr */
	copy            %arg2,%r29              /* init middle loop count */

fdtonemiddle:                                   /* Loop if LOOP = 1 */
	ADDIB>          -1,%r29,fdtonemiddle    /* Middle loop count decr */
	pdtlbe,m        %arg1(%sr1,%r28)        /* pdtlbe for one loop */

	ADDIB>          -1,%r22,fdtoneloop      /* Outer loop count decr */
	add             %r21,%r20,%r20          /* increment space */

fdtdone:

	/* Switch back to virtual mode */

	rsm     PSW_SM_Q,%r0       /* clear Q bit to load iia queue */
	ldil	L%KERNEL_PSW, %r1
	ldo	R%KERNEL_PSW(%r1), %r1
	or      %r1,%r19,%r1    /* Set I bit if set on entry */
	mtctl	%r1, %cr22
	mtctl	%r0, %cr17	/* Clear IIASQ tail */
	mtctl	%r0, %cr17	/* Clear IIASQ head */
	ldil    L%(2f), %r1
	ldo     R%(2f)(%r1), %r1
	mtctl	%r1, %cr18	/* IIAOQ head */
	ldo	4(%r1), %r1
	mtctl	%r1, %cr18	/* IIAOQ tail */
	rfi
	nop

2:      bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_instruction_cache_local,code
	.import cache_info,data

flush_instruction_cache_local:
	.proc
	.callinfo NO_CALLS
	.entry

	mtsp            %r0,%sr1
	ldil            L%cache_info,%r1
	ldo             R%cache_info(%r1),%r1

	/* Flush Instruction Cache */

	LDREG           ICACHE_BASE(%r1),%arg0
	LDREG           ICACHE_STRIDE(%r1),%arg1
	LDREG           ICACHE_COUNT(%r1),%arg2
	LDREG           ICACHE_LOOP(%r1),%arg3
	ADDIB=          -1,%arg3,fioneloop      /* Preadjust and test */
	movb,<,n        %arg3,%r31,fisync       /* If loop < 0, do sync */

fimanyloop:                                     /* Loop if LOOP >= 2 */
	ADDIB>          -1,%r31,fimanyloop      /* Adjusted inner loop decr */
	fice            0(%sr1,%arg0)
	fice,m          %arg1(%sr1,%arg0)       /* Last fice and addr adjust */
	movb,tr         %arg3,%r31,fimanyloop   /* Re-init inner loop count */
	ADDIB<=,n       -1,%arg2,fisync         /* Outer loop decr */

fioneloop:                                      /* Loop if LOOP = 1 */
	ADDIB>          -1,%arg2,fioneloop      /* Outer loop count decr */
	fice,m          %arg1(%sr1,%arg0)       /* Fice for one loop */

fisync:
	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_data_cache_local,code
	.import cache_info,data

flush_data_cache_local:
	.proc
	.callinfo NO_CALLS
	.entry

	mtsp            %r0,%sr1
	ldil            L%cache_info,%r1
	ldo             R%cache_info(%r1),%r1

	/* Flush Data Cache */

	LDREG           DCACHE_BASE(%r1),%arg0
	LDREG           DCACHE_STRIDE(%r1),%arg1
	LDREG           DCACHE_COUNT(%r1),%arg2
	LDREG           DCACHE_LOOP(%r1),%arg3
	rsm             PSW_SM_I,%r22
	ADDIB=          -1,%arg3,fdoneloop      /* Preadjust and test */
	movb,<,n        %arg3,%r31,fdsync       /* If loop < 0, do sync */

fdmanyloop:                                     /* Loop if LOOP >= 2 */
	ADDIB>          -1,%r31,fdmanyloop      /* Adjusted inner loop decr */
	fdce            0(%sr1,%arg0)
	fdce,m          %arg1(%sr1,%arg0)       /* Last fdce and addr adjust */
	movb,tr         %arg3,%r31,fdmanyloop   /* Re-init inner loop count */
	ADDIB<=,n       -1,%arg2,fdsync         /* Outer loop decr */

fdoneloop:                                      /* Loop if LOOP = 1 */
	ADDIB>          -1,%arg2,fdoneloop      /* Outer loop count decr */
	fdce,m          %arg1(%sr1,%arg0)       /* Fdce for one loop */

fdsync:
	syncdma
	sync
	mtsm    %r22
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export copy_user_page_asm,code

copy_user_page_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	ldi 64,%r1

	/*
	 * This loop is optimized for PCXL/PCXL2 ldw/ldw and stw/stw
	 * bundles (very restricted rules for bundling). It probably
	 * does OK on PCXU and better, but we could do better with
	 * ldd/std instructions. Note that until (if) we start saving
	 * the full 64 bit register values on interrupt, we can't
	 * use ldd/std on a 32 bit kernel.
	 */


1:
	ldw 0(%r25),%r19
	ldw 4(%r25),%r20
	ldw 8(%r25),%r21
	ldw 12(%r25),%r22
	stw %r19,0(%r26)
	stw %r20,4(%r26)
	stw %r21,8(%r26)
	stw %r22,12(%r26)
	ldw 16(%r25),%r19
	ldw 20(%r25),%r20
	ldw 24(%r25),%r21
	ldw 28(%r25),%r22
	stw %r19,16(%r26)
	stw %r20,20(%r26)
	stw %r21,24(%r26)
	stw %r22,28(%r26)
	ldw 32(%r25),%r19
	ldw 36(%r25),%r20
	ldw 40(%r25),%r21
	ldw 44(%r25),%r22
	stw %r19,32(%r26)
	stw %r20,36(%r26)
	stw %r21,40(%r26)
	stw %r22,44(%r26)
	ldw 48(%r25),%r19
	ldw 52(%r25),%r20
	ldw 56(%r25),%r21
	ldw 60(%r25),%r22
	stw %r19,48(%r26)
	stw %r20,52(%r26)
	stw %r21,56(%r26)
	stw %r22,60(%r26)
	ldo 64(%r26),%r26
	ADDIB>  -1,%r1,1b
	ldo 64(%r25),%r25

	bv      %r0(%r2)
	nop
	.exit

	.procend

#if (TMPALIAS_MAP_START >= 0x80000000UL)
Warning TMPALIAS_MAP_START changed. If > 2 Gb, code in pacache.S is bogus
#endif

/*
 * NOTE: Code in clear_user_page has a hard coded dependency on the
 *       maximum alias boundary being 4 Mb. We've been assured by the
 *       parisc chip designers that there will not ever be a parisc
 *       chip with a larger alias boundary (Never say never :-) ).
 *
 *       Subtle: the dtlb miss handlers support the temp alias region by
 *       "knowing" that if a dtlb miss happens within the temp alias
 *       region it must have occurred while in clear_user_page. Since
 *       this routine makes use of processor local translations, we
 *       don't want to insert them into the kernel page table. Instead,
 *       we load up some general registers (they need to be registers
 *       which aren't shadowed) with the physical page numbers (preshifted
 *       for tlb insertion) needed to insert the translations. When we
 *       miss on the translation, the dtlb miss handler inserts the
 *       translation into the tlb using these values:
 *
 *          %r26 physical page (shifted for tlb insert) of "to" translation
 *          %r23 physical page (shifted for tlb insert) of "from" translation
 */

#if 0

	/*
	 * We can't do this since copy_user_page is used to bring in
	 * file data that might have instructions. Since the data would
	 * then need to be flushed out so the i-fetch can see it, it
	 * makes more sense to just copy through the kernel translation
	 * and flush it.
	 *
	 * I'm still keeping this around because it may be possible to
	 * use it if more information is passed into copy_user_page().
	 * Have to do some measurements to see if it is worthwhile to
	 * lobby for such a change.
	 */

	.export copy_user_page_asm,code

copy_user_page_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%(__PAGE_OFFSET),%r1
	sub     %r26,%r1,%r26
	sub     %r25,%r1,%r23  /* move physical addr into non shadowed reg */

	ldil    L%(TMPALIAS_MAP_START),%r28
#ifdef __LP64__
	extrd,u %r26,56,32,%r26 /* convert phys addr to tlb insert format */
	extrd,u %r23,56,32,%r23 /* convert phys addr to tlb insert format */
	depd    %r24,63,22,%r28 /* Form aliased virtual address 'to' */
	depdi   0,63,12,%r28    /* Clear any offset bits */
	copy    %r28,%r29
	depdi   1,41,1,%r29     /* Form aliased virtual address 'from' */
#else
	extrw,u %r26,24,25,%r26 /* convert phys addr to tlb insert format */
	extrw,u %r23,24,25,%r23 /* convert phys addr to tlb insert format */
	depw    %r24,31,22,%r28 /* Form aliased virtual address 'to' */
	depwi   0,31,12,%r28    /* Clear any offset bits */
	copy    %r28,%r29
	depwi   1,9,1,%r29      /* Form aliased virtual address 'from' */
#endif

	/* Purge any old translations */

	pdtlb   0(%r28)
	pdtlb   0(%r29)

	ldi 64,%r1

	/*
	 * This loop is optimized for PCXL/PCXL2 ldw/ldw and stw/stw
	 * bundles (very restricted rules for bundling). It probably
	 * does OK on PCXU and better, but we could do better with
	 * ldd/std instructions. Note that until (if) we start saving
	 * the full 64 bit register values on interrupt, we can't
	 * use ldd/std on a 32 bit kernel.
	 */


1:
	ldw 0(%r29),%r19
	ldw 4(%r29),%r20
	ldw 8(%r29),%r21
	ldw 12(%r29),%r22
	stw %r19,0(%r28)
	stw %r20,4(%r28)
	stw %r21,8(%r28)
	stw %r22,12(%r28)
	ldw 16(%r29),%r19
	ldw 20(%r29),%r20
	ldw 24(%r29),%r21
	ldw 28(%r29),%r22
	stw %r19,16(%r28)
	stw %r20,20(%r28)
	stw %r21,24(%r28)
	stw %r22,28(%r28)
	ldw 32(%r29),%r19
	ldw 36(%r29),%r20
	ldw 40(%r29),%r21
	ldw 44(%r29),%r22
	stw %r19,32(%r28)
	stw %r20,36(%r28)
	stw %r21,40(%r28)
	stw %r22,44(%r28)
	ldw 48(%r29),%r19
	ldw 52(%r29),%r20
	ldw 56(%r29),%r21
	ldw 60(%r29),%r22
	stw %r19,48(%r28)
	stw %r20,52(%r28)
	stw %r21,56(%r28)
	stw %r22,60(%r28)
	ldo 64(%r28),%r28
	ADDIB>  -1,%r1,1b
	ldo 64(%r29),%r29

	bv      %r0(%r2)
	nop
	.exit

	.procend
#endif

	.export clear_user_page_asm,code

clear_user_page_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	tophys_r1 %r26

	ldil    L%(TMPALIAS_MAP_START),%r28
#ifdef __LP64__
	extrd,u %r26,56,32,%r26 /* convert phys addr to tlb insert format */
	depd    %r25,63,22,%r28 /* Form aliased virtual address 'to' */
	depdi   0,63,12,%r28    /* Clear any offset bits */
#else
	extrw,u %r26,24,25,%r26 /* convert phys addr to tlb insert format */
	depw    %r25,31,22,%r28 /* Form aliased virtual address 'to' */
	depwi   0,31,12,%r28    /* Clear any offset bits */
#endif

	/* Purge any old translation */

	pdtlb   0(%r28)

	ldi 64,%r1

1:
	stw %r0,0(%r28)
	stw %r0,4(%r28)
	stw %r0,8(%r28)
	stw %r0,12(%r28)
	stw %r0,16(%r28)
	stw %r0,20(%r28)
	stw %r0,24(%r28)
	stw %r0,28(%r28)
	stw %r0,32(%r28)
	stw %r0,36(%r28)
	stw %r0,40(%r28)
	stw %r0,44(%r28)
	stw %r0,48(%r28)
	stw %r0,52(%r28)
	stw %r0,56(%r28)
	stw %r0,60(%r28)
	ADDIB>  -1,%r1,1b
	ldo 64(%r28),%r28

	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_kernel_dcache_page

flush_kernel_dcache_page:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%dcache_stride,%r1
	ldw     R%dcache_stride(%r1),%r23

#ifdef __LP64__
	depdi,z 1,63-PAGE_SHIFT,1,%r25
#else
	depwi,z 1,31-PAGE_SHIFT,1,%r25
#endif
	add     %r26,%r25,%r25
	sub     %r25,%r23,%r25


1:      fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	fdc,m   %r23(%r26)
	CMPB<<  %r26,%r25,1b
	fdc,m   %r23(%r26)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export purge_kernel_dcache_page

purge_kernel_dcache_page:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%dcache_stride,%r1
	ldw     R%dcache_stride(%r1),%r23

#ifdef __LP64__
	depdi,z 1,63-PAGE_SHIFT,1,%r25
#else
	depwi,z 1,31-PAGE_SHIFT,1,%r25
#endif
	add      %r26,%r25,%r25
	sub      %r25,%r23,%r25

1:      pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	pdc,m   %r23(%r26)
	CMPB<<  %r26,%r25,1b
	pdc,m   %r23(%r26)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

#if 0
	/* Currently not used, but it still is a possible alternate
	 * solution.
	 */

	.export flush_alias_page

flush_alias_page:
	.proc
	.callinfo NO_CALLS
	.entry

	tophys_r1 %r26

	ldil    L%(TMPALIAS_MAP_START),%r28
#ifdef __LP64__
	extrd,u %r26,56,32,%r26 /* convert phys addr to tlb insert format */
	depd    %r25,63,22,%r28 /* Form aliased virtual address 'to' */
	depdi   0,63,12,%r28    /* Clear any offset bits */
#else
	extrw,u %r26,24,25,%r26 /* convert phys addr to tlb insert format */
	depw    %r25,31,22,%r28 /* Form aliased virtual address 'to' */
	depwi   0,31,12,%r28    /* Clear any offset bits */
#endif

	/* Purge any old translation */

	pdtlb   0(%r28)

	ldil    L%dcache_stride,%r1
	ldw     R%dcache_stride(%r1),%r23

#ifdef __LP64__
	depdi,z 1,63-PAGE_SHIFT,1,%r29
#else
	depwi,z 1,31-PAGE_SHIFT,1,%r29
#endif
	add      %r28,%r29,%r29
	sub      %r29,%r23,%r29

1:      fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	fdc,m   %r23(%r28)
	CMPB<<  %r28,%r29,1b
	fdc,m   %r23(%r28)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend
#endif

	.export flush_user_dcache_range_asm

flush_user_dcache_range_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%dcache_stride,%r1
	ldw     R%dcache_stride(%r1),%r23
	ldo     -1(%r23),%r21
	ANDCM   %r26,%r21,%r26

1:      CMPB<<,n %r26,%r25,1b
	fdc,m   %r23(%sr3,%r26)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_kernel_dcache_range_asm

flush_kernel_dcache_range_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%dcache_stride,%r1
	ldw     R%dcache_stride(%r1),%r23
	ldo     -1(%r23),%r21
	ANDCM   %r26,%r21,%r26

1:      CMPB<<,n %r26,%r25,1b
	fdc,m   %r23(%r26)

	sync
	syncdma
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_user_icache_range_asm

flush_user_icache_range_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%icache_stride,%r1
	ldw     R%icache_stride(%r1),%r23
	ldo     -1(%r23),%r21
	ANDCM   %r26,%r21,%r26

1:      CMPB<<,n %r26,%r25,1b
	fic,m   %r23(%sr3,%r26)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_kernel_icache_page

flush_kernel_icache_page:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%icache_stride,%r1
	ldw     R%icache_stride(%r1),%r23

#ifdef __LP64__
	depdi,z 1,63-PAGE_SHIFT,1,%r25
#else
	depwi,z 1,31-PAGE_SHIFT,1,%r25
#endif
	add     %r26,%r25,%r25
	sub     %r25,%r23,%r25


1:      fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	fic,m   %r23(%r26)
	CMPB<<  %r26,%r25,1b
	fic,m   %r23(%r26)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.export flush_kernel_icache_range_asm

flush_kernel_icache_range_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	ldil    L%icache_stride,%r1
	ldw     R%icache_stride(%r1),%r23
	ldo     -1(%r23),%r21
	ANDCM   %r26,%r21,%r26

1:      CMPB<<,n %r26,%r25,1b
	fic,m   %r23(%r26)

	sync
	bv      %r0(%r2)
	nop
	.exit

	.procend

	.align 128

	.export disable_sr_hashing_asm,code

disable_sr_hashing_asm:
	.proc
	.callinfo NO_CALLS
	.entry

	/* Switch to real mode */

	ssm     0,%r0           /* relied upon translation! */
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	
	rsm     (PSW_SM_Q|PSW_SM_I),%r0 /* disable Q&I to load the iia queue */
	ldil    L%REAL_MODE_PSW, %r1
	ldo     R%REAL_MODE_PSW(%r1), %r1
	mtctl	%r1, %cr22
	mtctl	%r0, %cr17	/* Clear IIASQ tail */
	mtctl	%r0, %cr17	/* Clear IIASQ head */
	ldil    L%PA(1f),%r1
	ldo     R%PA(1f)(%r1),%r1
	mtctl	%r1, %cr18	/* IIAOQ head */
	ldo	4(%r1), %r1
	mtctl	%r1, %cr18	/* IIAOQ tail */
	rfi
	nop

1:      cmpib,=,n SRHASH_PCXST,%r26,srdis_pcxs
	cmpib,=,n SRHASH_PCXL,%r26,srdis_pcxl
	cmpib,=,n SRHASH_PA20,%r26,srdis_pa20
	b,n       srdis_done

srdis_pcxs:

	/* Disable Space Register Hashing for PCXS,PCXT,PCXT' */

	.word           0x141c1a00  /* mfdiag %dr0,%r28 */
	.word           0x141c1a00  /* must issue twice */
	depwi           0,18,1,%r28 /* Clear DHE (dcache hash enable) */
	depwi           0,20,1,%r28 /* Clear IHE (icache hash enable) */
	.word           0x141c1600  /* mtdiag %r28,%dr0 */
	.word           0x141c1600  /* must issue twice */
	b,n             srdis_done

srdis_pcxl:

	/* Disable Space Register Hashing for PCXL */

	.word           0x141c0600  /* mfdiag %dr0,%r28 */
	depwi           0,28,2,%r28 /* Clear DHASH_EN & IHASH_EN */
	.word           0x141c0240  /* mtdiag %r28,%dr0 */
	b,n             srdis_done

srdis_pa20:

	/* Disable Space Register Hashing for PCXU,PCXU+,PCXW,PCXW+ */

	.word           0x144008bc  /* mfdiag %dr2,%r28 */
	depdi           0,54,1,%r28 /* clear DIAG_SPHASH_ENAB (bit 54) */
	.word           0x145c1840  /* mtdiag %r28,%dr2 */

srdis_done:

	/* Switch back to virtual mode */

	rsm     PSW_SM_Q,%r0           /* clear Q bit to load iia queue */
	ldil	L%KERNEL_PSW, %r1
	ldo	R%KERNEL_PSW(%r1), %r1
	mtctl	%r1, %cr22
	mtctl	%r0, %cr17	/* Clear IIASQ tail */
	mtctl	%r0, %cr17	/* Clear IIASQ head */
	ldil    L%(2f), %r1
	ldo     R%(2f)(%r1), %r1
	mtctl	%r1, %cr18	/* IIAOQ head */
	ldo	4(%r1), %r1
	mtctl	%r1, %cr18	/* IIAOQ tail */
	rfi
	nop

2:      bv      %r0(%r2)
	nop
	.exit

	.procend

	.end
