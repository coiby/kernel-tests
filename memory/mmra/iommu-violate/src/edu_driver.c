#include <linux/cdev.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/kernel.h>
#include <linux/ktime.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/uaccess.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Filippo Storniolo");
MODULE_DESCRIPTION("Simulate a hardware device using the QEMU edu driver to "
                   "trigger invalid memory access, generating vIOMMU page "
                   "faults to verify the kernel's behavior.");
MODULE_VERSION("1.0");

#define EDU_PCI_BAR 0

#define EDU_DEV_NAME "qemu-edu-driver"
#define EDU_DEVICE_ID 0x11e8
#define QEMU_VENDOR_ID 0x1234

#define EDU_IO_IRQ_STATUS 0x24
#define EDU_IO_IRQ_ACK 0x64
#define EDU_IO_DMA_SRC 0x80
#define EDU_IO_DMA_DST 0x88
#define EDU_IO_DMA_CNT 0x90
#define EDU_IO_DMA_CMD 0x98

#define EDU_DMA_BASE 0x40000
#define EDU_DMA_CMD 0x1
#define EDU_DMA_FROM_DEV 0x2
#define EDU_DMA_IRQ 0x4

#define DMA_OPERATION_TIMEOUT_SECONDS (10 * NSEC_PER_SEC)
#define MAX_EDU_DEVICE_FILE_NAME 128

static struct dentry *edu_driver_dir;

static struct pci_device_id pci_ids[] = {
    {
        PCI_DEVICE(QEMU_VENDOR_ID, EDU_DEVICE_ID),
    },
    {
        0,
    }};

struct edu_device_context {
  struct dentry *edu_device_file;
  dma_addr_t dma_handle_from;
  dma_addr_t dma_handle_to;
  void *dma_vaddr_from;
  void *dma_vaddr_to;
  void __iomem *mmio;
};

MODULE_DEVICE_TABLE(pci, pci_ids);

static atomic_t edu_device_counter = ATOMIC_INIT(0);

static ssize_t edu_driver_test_write(struct file *file,
                                     const char __user *user_buf, size_t count,
                                     loff_t *ppos);

static const struct file_operations edu_driver_test_fops = {
    .write = edu_driver_test_write,
};

static inline int dma_io_wait(void __iomem *mmio) {
  ktime_t start_time, current_time;
  start_time = ktime_get();

  while (ioread32(mmio + EDU_IO_DMA_CMD) & 1) {
    current_time = ktime_get();

    if (ktime_after(current_time,
                    ktime_add_ns(start_time, DMA_OPERATION_TIMEOUT_SECONDS)))
      return -ETIMEDOUT;

    msleep(10);
  }

  return 0;
}

static inline void setup_dma_operation(void __iomem *mmio, uint64_t src,
                                       uint64_t dst, uint64_t count,
                                       uint64_t flags) {
  // configure the device for a dma operation
  writeq(src, mmio + EDU_IO_DMA_SRC);
  writeq(dst, mmio + EDU_IO_DMA_DST);
  writeq(count, mmio + EDU_IO_DMA_CNT);
  writeq(flags, mmio + EDU_IO_DMA_CMD);
}

static int test_write_read_dma_with_fault_on_invalid(struct pci_dev *dev) {
  struct edu_device_context *ctx = pci_get_drvdata(dev);
  uint64_t invalid_address = 0xaabbccddeeff00;

  pr_info("TEST: test_write_read_dma_with_fault_on_invalid (page fault is "
          "expected)\n");

  // the concept of invalid address may vary changing hardware components
  // we are assuming 0xaabbccddeeff00 is an invalid address because in the
  // configuration we are using, the pci device has the dma_mask set to 64 bits,
  // while the iommu (emulated using virtio-iommu) is working with an IOVA
  // address width of 48 bits.

  // configure the device to read from an invalid address
  pr_info("configure the device to read from an invalid address\n");
  setup_dma_operation(ctx->mmio, invalid_address, EDU_DMA_BASE, 4, EDU_DMA_CMD);

  // poll on IO_DMA_CMD
  pr_info("poll on IO_DMA_CMD\n");
  return dma_io_wait(ctx->mmio);
}

static int test_write_read_dma_with_fault_on_unmapped(struct pci_dev *dev) {
  struct edu_device_context *ctx = pci_get_drvdata(dev);
  dma_addr_t dma_unmapped_address;
  void *va_unmapped_address;

  pr_info("TEST: test_write_read_dma_with_fault_on_unmapped (page fault is "
          "expected)\n");

  va_unmapped_address = dma_alloc_coherent(&(dev->dev), PAGE_SIZE,
                                           &dma_unmapped_address, GFP_KERNEL);
  if (va_unmapped_address == NULL)
    return -ENOMEM;

  dma_free_coherent(&(dev->dev), PAGE_SIZE, va_unmapped_address,
                    dma_unmapped_address);

  // configure the device to read from a non mapped page
  pr_info("configure the device to read from a non mapped page\n");
  setup_dma_operation(ctx->mmio, dma_unmapped_address, EDU_DMA_BASE, 4,
                      EDU_DMA_CMD);

  // poll on IO_DMA_CMD
  pr_info("poll on IO_DMA_CMD\n");
  return dma_io_wait(ctx->mmio);
}

static int test_write_read_dma_with_fault_on_readonly(struct pci_dev *dev) {
  struct edu_device_context *ctx = pci_get_drvdata(dev);
  struct page *pg = NULL;
  dma_addr_t dma_addr_ro;
  int ret;

  pr_info("TEST: test_write_read_dma_with_fault_on_readonly (page fault is "
          "expected)\n");

  // allocate one page
  pr_info("allocate one page\n");
  pg = alloc_page(GFP_KERNEL);
  if (!pg) {
    dev_info(&(dev->dev), "page allocation failed\n");
    return -ENOMEM;
  }

  // set the page read only for the device
  pr_info("set the page read only for the device\n");
  dma_addr_ro = dma_map_page(&dev->dev, pg, 0, PAGE_SIZE, DMA_TO_DEVICE);
  if (dma_mapping_error(&dev->dev, dma_addr_ro)) {
    ret = -ENOMEM;
    dev_info(&(dev->dev), "dma mapping failed\n");
    goto error_dma_map_page;
  }

  // configure the device to read from a readable page
  pr_info("configure the device to read from a readable page\n");
  setup_dma_operation(ctx->mmio, ctx->dma_handle_from, EDU_DMA_BASE, 4,
                      EDU_DMA_CMD);

  // poll on IO_DMA_CMD
  pr_info("poll on IO_DMA_CMD\n");
  ret = dma_io_wait(ctx->mmio);
  if (ret)
    goto error_dma_io_wait;

  // configure the device to write in a read only page
  pr_info("configure the device to write in a read only page\n");
  setup_dma_operation(ctx->mmio, EDU_DMA_BASE, dma_addr_ro, 4,
                      EDU_DMA_CMD | EDU_DMA_FROM_DEV);

  // poll on IO_DMA_CMD
  pr_info("poll on IO_DMA_CMD\n");
  ret = dma_io_wait(ctx->mmio);
  if (ret)
    goto error_dma_io_wait;

  dma_unmap_page(&dev->dev, dma_addr_ro, PAGE_SIZE, DMA_TO_DEVICE);

  // remove the page
  pr_info("remove the page\n");
  __free_page(pg);
  return 0;

error_dma_io_wait:
  dma_unmap_page(&dev->dev, dma_addr_ro, PAGE_SIZE, DMA_TO_DEVICE);
error_dma_map_page:
  __free_page(pg);
  return ret;
}

static ssize_t edu_driver_test_write(struct file *file,
                                     const char __user *user_buf, size_t count,
                                     loff_t *ppos) {
  struct pci_dev *dev = file->f_inode->i_private;
  char scenario[256];
  int ret;

  // Check if user data will fit into the kernel buffer while leaving space for
  // a null-terminator.
  if (count > sizeof(scenario) - 1) {
    pr_info("string is too big\n");
    return -E2BIG;
  }

  // Copy user data to the kernel buffer
  if (copy_from_user(scenario, user_buf, count)) {
    pr_info("Error occured while copying the user buffer\n");
    return -EFAULT;
  }

  // Null-terminate the string in the kernel buffer
  scenario[count] = '\0';

  if (strcmp(scenario, "test_invalid") == 0)
    // test with page fault on IOMMU due to accessing an invalid address
    ret = test_write_read_dma_with_fault_on_invalid(dev);
  else if (strcmp(scenario, "test_read_only") == 0)
    // test with page fault on IOMMU due to attempting a write operation on a
    // read only page
    ret = test_write_read_dma_with_fault_on_readonly(dev);
  else if (strcmp(scenario, "test_unmapped") == 0)
    // test with page fault on IOMMU due to attempting a write operation on a
    // unmapped page
    ret = test_write_read_dma_with_fault_on_unmapped(dev);
  else {
    pr_info("'%s' is not a valid test\n", scenario);
    return -EINVAL;
  }

  return ret ? ret : count;
}

static int pci_probe(struct pci_dev *dev, const struct pci_device_id *id) {
  char edu_driver_test_file_name[MAX_EDU_DEVICE_FILE_NAME];
  struct edu_device_context *ctx;
  int edu_file_id;
  int len;
  int err;

  err = pci_enable_device(dev);
  if (err) {
    dev_err(&(dev->dev), "error occured while executing pci_enable_device\n");
    return err;
  }

  pci_set_master(dev);

  err = pci_request_region(dev, EDU_PCI_BAR, "myregion0");
  if (err) {
    dev_err(&(dev->dev), "error occured while executing pci_request_region\n");
    goto error_pci_request_region;
  }

  ctx = kmalloc(sizeof(struct edu_device_context), GFP_KERNEL);
  if (!ctx) {
    err = -ENOMEM;
    goto error_kmalloc;
  }

  pci_set_drvdata(dev, ctx);

  ctx->mmio = pci_iomap(dev, EDU_PCI_BAR, pci_resource_len(dev, EDU_PCI_BAR));
  if (ctx->mmio == NULL) {
    err = -ENOMEM;
    goto error_pci_iomap;
  }

  ctx->dma_vaddr_from = dma_alloc_coherent(&(dev->dev), PAGE_SIZE,
                                           &ctx->dma_handle_from, GFP_KERNEL);
  if (ctx->dma_vaddr_from == NULL) {
    err = -ENOMEM;
    goto error_dma_alloc_coherent_from;
  }

  ctx->dma_vaddr_to = dma_alloc_coherent(&(dev->dev), PAGE_SIZE,
                                         &ctx->dma_handle_to, GFP_KERNEL);
  if (ctx->dma_vaddr_to == NULL) {
    err = -ENOMEM;
    goto error_dma_alloc_coherent_to;
  }

  edu_file_id = atomic_inc_return(&edu_device_counter);

  len = snprintf(edu_driver_test_file_name, MAX_EDU_DEVICE_FILE_NAME,
                 "edu_driver_test_%d", edu_file_id);
  if (len < 0 || len >= MAX_EDU_DEVICE_FILE_NAME) {
    dev_err(&(dev->dev), "cant create string\n");
    err = -E2BIG;
    goto error_debugfs_create_file;
  }

  ctx->edu_device_file =
      debugfs_create_file(edu_driver_test_file_name, 0644, edu_driver_dir, dev,
                          &edu_driver_test_fops);
  if (IS_ERR(ctx->edu_device_file)) {
    err = PTR_ERR(ctx->edu_device_file);
    goto error_debugfs_create_file;
  }

  return 0;

error_debugfs_create_file:
  dma_free_coherent(&(dev->dev), PAGE_SIZE, ctx->dma_vaddr_to,
                    ctx->dma_handle_to);
error_dma_alloc_coherent_to:
  dma_free_coherent(&(dev->dev), PAGE_SIZE, ctx->dma_vaddr_from,
                    ctx->dma_handle_from);
error_dma_alloc_coherent_from:
  iounmap(ctx->mmio);
error_pci_iomap:
  kfree(ctx);
error_kmalloc:
  pci_release_region(dev, EDU_PCI_BAR);
error_pci_request_region:
  pci_disable_device(dev);

  return err;
}

static void pci_remove(struct pci_dev *dev) {
  struct edu_device_context *ctx = pci_get_drvdata(dev);

  debugfs_remove(ctx->edu_device_file);
  dma_free_coherent(&(dev->dev), PAGE_SIZE, ctx->dma_vaddr_to,
                    ctx->dma_handle_to);
  dma_free_coherent(&(dev->dev), PAGE_SIZE, ctx->dma_vaddr_from,
                    ctx->dma_handle_from);
  iounmap(ctx->mmio);
  kfree(ctx);
  pci_release_region(dev, EDU_PCI_BAR);
  pci_disable_device(dev);
}

static struct pci_driver edu_driver = {
    .name = EDU_DEV_NAME,
    .id_table = pci_ids,
    .probe = pci_probe,
    .remove = pci_remove,
};

static int init_driver(void) {
  pr_info("edu_driver module initializing\n");
  edu_driver_dir = debugfs_create_dir("edu_driver", NULL);
  if (IS_ERR(edu_driver_dir))
    return PTR_ERR(edu_driver_dir);

  return pci_register_driver(&edu_driver);
}

static void exit_driver(void) {
  pr_info("edu_driver module exiting\n");
  pci_unregister_driver(&edu_driver);

  // remove the directory after every file in it,
  // once per device, is deleted by the pci_remove callback
  debugfs_remove(edu_driver_dir);
}

module_init(init_driver);
module_exit(exit_driver);
MODULE_LICENSE("GPL");
