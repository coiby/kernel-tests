#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/debugfs.h>
#include <linux/gfp.h>
#include <linux/mm.h>

#if defined (PAGETABLE_LEVELS) && (PAGETABLE_LEVELS <= 4)
#include <asm/cacheflush.h>
#elif defined (CONFIG_PGTABLE_LEVELS) && (CONFIG_PGTABLE_LEVELS == 5)
#include <linux/set_memory.h>
#define sup5lvl
#else
#error "Can't determine page table level"
#endif

static void print_pgtable_entries_pgd(void *vaddr, pgd_t *pgd)
{
	unsigned long address = (unsigned long)vaddr;
	unsigned long base, idx;
#if defined(sup5lvl)
	p4d_t *p4d;
#endif
	pud_t *pud;
	pmd_t *pmd;
	pte_t *pte;

	if (!pgd || !pgd_present(*pgd))
		return;

	base = pgd_val(*pgd) & PTE_PFN_MASK;
#if defined(sup5lvl)
	idx = p4d_index(address);
	p4d = p4d_offset(pgd, address);
	pr_alert("VMGuard:  P4D: Base=%#018lx, Index=%03lu, Offset=%#05lx, Entry=%#018lx%s\n",
		 base, idx, idx * sizeof(p4d_t), p4d_val(*p4d), p4d_val(*p4d) & sme_me_mask ? " (encrypted)" : "");
	if (!p4d_present(*p4d))
		return;

	base = p4d_val(*p4d) & PTE_PFN_MASK;
#endif
	idx = pud_index(address);
#if defined(sup5lvl)
	pud = pud_offset(p4d, address);
#else
	pud = pud_offset(pgd, address);
#endif
	pr_alert("VMGuard:  PUD: Base=%#018lx, Index=%03lu, Offset=%#05lx, Entry=%#018lx%s\n",
		base, idx, idx * sizeof(pud_t), pud_val(*pud), pud_val(*pud) & sme_me_mask ? " (encrypted)" : "");
	if (!pud_present(*pud))
		return;
#ifndef OLD_RHEL
	if (pud_leaf(*pud)) {
		pr_alert("VMGuard:  Address %#018lx at physical address %#018lx\n",
			address, (pud_val(*pud) & PTE_PFN_MASK) + (address & ~PUD_MASK));
#else
	if (pud_large(*pud)) {
		pr_alert("VMGuard:  Address %#018lx at physical address %#018lx\n",
			 address, (pud_val(*pud) & PTE_PFN_MASK) + (address & ~PUD_PAGE_MASK));
#endif
		return;
	}

	base = pud_val(*pud) & PTE_PFN_MASK;
	idx = pmd_index(address);
	pmd = pmd_offset(pud, address);
	pr_alert("VMGuard:  PMD: Base=%#018lx, Index=%03lu, Offset=%#05lx, Entry=%#018lx%s\n",
		 base, idx, idx * sizeof(pmd_t), pmd_val(*pmd), pmd_val(*pmd) & sme_me_mask ? " (encrypted)" : "");
	if (!pmd_present(*pmd))
		return;
#ifndef OLD_RHEL
	if (pmd_leaf(*pmd)) {
		pr_alert("VMGuard:  Address %#018lx at physical address %#018lx\n",
			 address, (pmd_val(*pmd) & PTE_PFN_MASK) + (address & ~PMD_MASK));
#else
	if (pmd_large(*pmd)) {
		pr_alert("VMGuard:  Address %#018lx at physical address %#018lx\n",
			 address, (pmd_val(*pmd) & PTE_PFN_MASK) + (address & ~PMD_PAGE_MASK));
#endif
		return;
	}

	base = pmd_val(*pmd) & PTE_PFN_MASK;
	idx = pte_index(address);
	pte = pte_offset_kernel(pmd, address);
	pr_alert("VMGuard:  PTD: Base=%#018lx, Index=%03lu, Offset=%#05lx, Entry=%#018lx%s\n",
		 base, idx, idx * sizeof(pte_t), pte_val(*pte), pte_val(*pte) & sme_me_mask ? " (encrypted)" : "");
	if (!pte_present(*pte))
		return;

	pr_alert("VMGuard:  Address %#018lx at physical address %#018lx\n",
		 address, (pte_val(*pte) & PTE_PFN_MASK) + (address & ~PAGE_MASK));
}

static void print_pgtable_entries(void *vaddr)
{
	unsigned long address = (unsigned long)vaddr;
	unsigned long base, idx;
	pgd_t *pgd;

	pr_alert("VMGuard: Pagetable entries for %#018lx:\n", address);

	base = read_cr3_pa();
	idx = pgd_index(address);
	pgd = __va(base);
	pgd += idx;
	pr_alert("VMGuard:  PGD: Base=%#018lx, Index=%03lu, Offset=%#05lx, Entry=%#018lx%s\n",
		 base, idx, idx * sizeof(pgd_t), pgd_val(*pgd), pgd_val(*pgd) & sme_me_mask ? " (encrypted)" : "");

	print_pgtable_entries_pgd(vaddr, pgd);
}

static int __init smetest_init(void)
{
	struct page *sme_page;
	unsigned int *sme_mem;
	int i;

	pr_alert("Entering smetest\n");

	sme_page = alloc_pages(GFP_KERNEL, 0);
	if (!sme_page)
		return -ENOMEM;

	sme_mem = (unsigned int *)page_address(sme_page);
	for (i = 0; i < (PAGE_SIZE / sizeof(*sme_mem)); i++)
		sme_mem[i] = 0xdeadbeef;

	pr_alert("Current pagetable entries and memory contents for 0x%p\n", sme_mem);
	print_pgtable_entries(sme_mem);
	print_hex_dump(KERN_ALERT, "SMEtest: ", DUMP_PREFIX_ADDRESS, 32, 4, sme_mem, 128, 0);
	pr_alert("\n");

	/* Changes the attributes, but not the data */
	pr_alert("Changing memory attributes to decrypted\n");
	set_memory_decrypted((unsigned long)sme_mem, 1);
	print_pgtable_entries(sme_mem);
	print_hex_dump(KERN_ALERT, "SMEtest: ", DUMP_PREFIX_ADDRESS, 32, 4, sme_mem, 128, 0);
	pr_alert("\n");

	pr_alert("Changing memory attributes to back to encrypted\n");
	set_memory_encrypted((unsigned long)sme_mem, 1);
	print_pgtable_entries(sme_mem);
	print_hex_dump(KERN_ALERT, "SMEtest: ", DUMP_PREFIX_ADDRESS, 32, 4, sme_mem, 128, 0);

	__free_page(sme_page);

	return -EAGAIN;
}

static void __exit smetest_exit(void)
{
}

module_init(smetest_init);
module_exit(smetest_exit);

MODULE_AUTHOR("Advanced Micro Devices, Inc.");
MODULE_DESCRIPTION("SME Test Module");
MODULE_LICENSE("GPL");
