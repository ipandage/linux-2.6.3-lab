/*
 * $Id: hitfb.c,v 1.10 2004/02/01 19:46:04 lethal Exp $
 * linux/drivers/video/hitfb.c -- Hitachi LCD frame buffer device
 * (C) 1999 Mihai Spatar
 * (C) 2000 YAEGASHI Takeshi
 * (C) 2003, 2004 Paul Mundt
 * (C) 2003 Andriy Skulysh
 *
 *  This file is subject to the terms and conditions of the GNU General Public
 *  License. See the file COPYING in the main directory of this archive for
 *  more details.
 */
 
#include <linux/config.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/errno.h>
#include <linux/string.h>
#include <linux/mm.h>
#include <linux/tty.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/fb.h>

#include <asm/machvec.h>
#include <asm/uaccess.h>
#include <asm/pgtable.h>
#include <asm/io.h>
#include <asm/hd64461/hd64461.h>

static struct fb_var_screeninfo hitfb_var __initdata = {
	.activate	= FB_ACTIVATE_NOW,
	.height		= -1,
	.width		= -1,
	.vmode		= FB_VMODE_NONINTERLACED,
};

static struct fb_fix_screeninfo hitfb_fix __initdata = {
	.id		= "Hitachi HD64461",
	.type		= FB_TYPE_PACKED_PIXELS,
	.ypanstep	= 8,
	.accel		= FB_ACCEL_NONE,
};

static u32 pseudo_palette[16];
static struct fb_info fb_info;


#define	WIDTH 640

static void hitfb_set_base(u32 offset)
{
	fb_writew(offset>>10,HD64461_LCDCBAR);
}

static inline void hitfb_accel_wait()
{
	while (fb_readw(HD64461_GRCFGR) & HD64461_GRCFGR_ACCSTATUS)
		;
}

static inline void hitfb_accel_start(int truecolor)
{
	if (truecolor) {
		fb_writew(6,HD64461_GRCFGR);
	} else {
		fb_writew(7,HD64461_GRCFGR);
	}
}

static inline void hitfb_accel_set_dest(int truecolor, u16 dx, u16 dy, 
	u16 width, u16 height)
{
	u32 saddr=WIDTH*dy+dx;
	if (truecolor)
		saddr <<= 1;
	
	fb_writew(width,HD64461_BBTDWR);
	fb_writew(height,HD64461_BBTDHR);
	
	fb_writew(saddr&0xffff,HD64461_BBTDSARL);
	fb_writew(saddr>>16,HD64461_BBTDSARH);
}

static inline void hitfb_accel_solidfill(int truecolor, u16 dx, u16 dy, 
	u16 width, u16 height, u16 color)
{
	hitfb_accel_set_dest(truecolor,dx,dy,width,height);

	fb_writew(0x00f0,HD64461_BBTROPR);
	fb_writew(16,HD64461_BBTMDR);
	fb_writew(color,HD64461_GRSCR);

	hitfb_accel_start(truecolor);
}

static inline void hitfb_accel_bitblt(int truecolor, u16 sx, u16 sy, u16 dx, u16 dy, 
	u16 width, u16 height, u16 rop, u32 mask_addr)
{
	u32 saddr,daddr;
	u32 maddr=0;
	fb_writew(rop,HD64461_BBTROPR);

	if((sy<dy)||((sy==dy)&&(sx<=dx))) {
		saddr=WIDTH*(sy+height)+sx+width;
		daddr=WIDTH*(dy+height)+dx+width;

		if (mask_addr) {
			if (truecolor) {
				maddr=((width>>3)+1)*(height+1)-1;
			} else {
				maddr=(((width>>4)+1)*(height+1)-1)*2;
			}

			fb_writew((1<<5)|1,HD64461_BBTMDR);
		} else {
			fb_writew(1,HD64461_BBTMDR);
		}
	} else {
		saddr=WIDTH*sy+sx;
		daddr=WIDTH*dy+dx;
		if (mask_addr) {
			fb_writew((1<<5),HD64461_BBTMDR);
		} else {
			outw(0,HD64461_BBTMDR);
		}
	}

	if (truecolor) {
		saddr<<=1;
		daddr<<=1;
	}

	fb_writew(width,HD64461_BBTDWR);
	fb_writew(height,HD64461_BBTDHR);
	fb_writew(saddr&0xffff,HD64461_BBTSSARL);
	fb_writew(saddr>>16,HD64461_BBTSSARH);
	fb_writew(daddr&0xffff,HD64461_BBTDSARL);
	fb_writew(daddr>>16,HD64461_BBTDSARH);

	if (mask_addr) {
		maddr+=mask_addr;
		fb_writew(maddr&0xffff,HD64461_BBTMARL);
		fb_writew(maddr>>16,HD64461_BBTMARH);
	}
	hitfb_accel_start(truecolor);
}

static void hitfb_fillrect(struct fb_info *p, const struct fb_fillrect *rect)
{
	if (rect->rop != ROP_COPY) {
		cfb_fillrect(p,rect);
	} else {
		fb_writew(0x00f0,HD64461_BBTROPR);
		fb_writew(16,HD64461_BBTMDR);

		if (p->var.bits_per_pixel==16) {
			fb_writew( ((u32*)(p->pseudo_palette))[rect->color] , HD64461_GRSCR );
			hitfb_accel_set_dest(1,rect->dx,rect->dy,rect->width,rect->height);
			hitfb_accel_start(1);
		} else {
			fb_writew(rect->color, HD64461_GRSCR);
			hitfb_accel_set_dest(0,rect->dx,rect->dy,rect->width,rect->height);
			hitfb_accel_start(0);
		}
		hitfb_accel_wait();
	}
}

static void hitfb_copyarea(struct fb_info *p, const struct fb_copyarea *area)
{
	hitfb_accel_bitblt(p->var.bits_per_pixel==16,area->sx,area->sy,
		area->dx,area->dy,area->width,area->height,0x00cc,0);
	hitfb_accel_wait();
}

static int hitfb_pan_display(struct fb_var_screeninfo *var,
			     struct fb_info *info)
{
    int xoffset = var->xoffset;
    int yoffset = var->yoffset;

    if (xoffset!=0)
		return -EINVAL;

    hitfb_set_base(yoffset*2*640);

    return 0;
}

int hitfb_blank(int blank_mode, struct fb_info *info)
{
	unsigned short v;

	if (blank_mode) {
		v = fb_readw(HD64461_LDR1);
		v &= ~HD64461_LDR1_DON;
		fb_writew(v, HD64461_LDR1);

		v = fb_readw(HD64461_LCDCCR);
		v |= HD64461_LCDCCR_MOFF;
		fb_writew(v, HD64461_LCDCCR);

		v = fb_readw(HD64461_STBCR);
		v |= HD64461_STBCR_SLCDST;
		fb_writew(v, HD64461_STBCR);
	} else {
		v = fb_readw(HD64461_STBCR);
		v &= ~HD64461_STBCR_SLCDST;
		fb_writew(v, HD64461_STBCR);

		v = fb_readw(HD64461_LDR1);
		v |= HD64461_LDR1_DON;
		fb_writew(v, HD64461_LDR1);

		v = fb_readw(HD64461_LCDCCR);
		v &= ~HD64461_LCDCCR_MOFF;
		fb_writew(v, HD64461_LCDCCR);
	}

	return 0;
}

static int hitfb_setcolreg(unsigned regno, unsigned red, unsigned green,
			   unsigned blue, unsigned transp,
			   struct fb_info *info)
{
	if (regno >= info->cmap.len)
		return 1;
    
	switch (info->var.bits_per_pixel) {
		case 8:
			fb_writew(regno << 8, HD64461_CPTWAR);
			fb_writew(red >> 10, HD64461_CPTWDR);
			fb_writew(green >> 10, HD64461_CPTWDR);
			fb_writew(blue >> 10, HD64461_CPTWDR);
			break;
		case 16:
			((u32*)(info->pseudo_palette))[regno] =
					((red   & 0xf800)      ) |
					((green & 0xfc00) >>  5) |
					((blue  & 0xf800) >> 11);
			break;
	}
	return 0;
}

static int hitfb_check_var(struct fb_var_screeninfo *var, struct fb_info *info)
{
	switch (hitfb_var.bits_per_pixel) {
	case 8:
		hitfb_var.red.offset = 0;
		hitfb_var.red.length = 8;
		hitfb_var.green.offset = 0;
		hitfb_var.green.length = 8;
		hitfb_var.blue.offset = 0;
		hitfb_var.blue.length = 8;
		hitfb_var.transp.offset = 0;
		hitfb_var.transp.length = 0;
		break;
	case 16:	/* RGB 565 */
		hitfb_var.red.offset = 11;
		hitfb_var.red.length = 5;
		hitfb_var.green.offset = 5;
		hitfb_var.green.length = 6;
		hitfb_var.blue.offset = 0;
		hitfb_var.blue.length = 5;
		hitfb_var.transp.offset = 0;
		hitfb_var.transp.length = 0;
		break;
	}

	return 0;
}

static struct fb_ops hitfb_ops = {
	.owner		= THIS_MODULE,
	.fb_check_var	= hitfb_check_var,
	.fb_set_par	= hitfb_set_par,
	.fb_setcolreg	= hitfb_setcolreg,
	.fb_pan_display = hitfb_pan_display,
	.fb_blank	= hitfb_blank,
	.fb_fillrect	= hitfb_fillrect,
	.fb_copyarea	= hitfb_copyarea,
	.fb_imageblit	= cfb_imageblit,
	.fb_cursor	= soft_cursor,
};

int __init hitfb_init(void)
{
	unsigned short lcdclor, ldr3, ldvndr;
	int size;

	hitfb_fix.smem_start = CONFIG_HD64461_IOBASE + 0x02000000;
	hitfb_fix.smem_len = (MACH_HP690) ? 1024*1024 : 512*1024;

	lcdclor = inw(HD64461_LCDCLOR);
	ldvndr = inw(HD64461_LDVNDR);
	ldr3 = inw(HD64461_LDR3);

	switch (ldr3&15) {
		default:
		case 4:
			hitfb_var.bits_per_pixel = 8;
			hitfb_var.xres = lcdclor;
			break;
		case 8:
			hitfb_var.bits_per_pixel = 16;
			hitfb_var.xres = lcdclor/2;
			break;
	}

	/* XXX: Most of this should go into hitfb_set_par().. --PFM. */
	hitfb_fix.line_length = lcdclor;
	hitfb_fix.visual = (hitfb_var.bits_per_pixel == 8) ?
		FB_VISUAL_PSEUDOCOLOR : FB_VISUAL_TRUECOLOR;
	hitfb_var.yres = ldvndr+1;
	hitfb_var.xres_virtual = hitfb_var.xres;
	hitfb_var.yres_virtual = hitfb_fix.smem_len/lcdclor;

	fb_info.fbops 		= &hitfb_ops;
	fb_info.var 		= hitfb_var;
	fb_info.fix 		= hitfb_fix;
	fb_info.pseudo_palette 	= pseudo_palette;	
	fb_info.flags 		= FBINFO_FLAG_DEFAULT;
    	
	fb_info.screen_base = (void *) hitfb_fix.smem_start;

	size = (fb_info.var.bits_per_pixel == 8) ? 256 : 16;
	fb_alloc_cmap(&fb_info.cmap, size, 0); 	

	if (register_framebuffer(&fb_info) < 0)
		return -EINVAL;
    
	printk(KERN_INFO "fb%d: %s frame buffer device\n",
			fb_info.node, fb_info.fix.id);
	return 0;
}

static void __exit hitfb_exit(void)
{
	unregister_framebuffer(&fb_info);
}

#ifdef MODULE
module_init(hitfb_init);
module_exit(hitfb_exit);
#endif

MODULE_LICENSE("GPL");

