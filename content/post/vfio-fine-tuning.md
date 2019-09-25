+++
categories = ["Linux"]
date = "2019-09-24"
title = "Fine-tuning a PCI-Passthrough vfio VM"
description = "Masking interrupt, shielding CPUs, and other techniques I have found useful for reducing latency and improving performance"
tags = ["vfio","gaming","kvm"]
images = []
draft = false
toc = true
+++

## Introduction

As a quick introduction, vfio is the name of the technology built in the linux kernel which allows to map io devices to kvm guests. The name is also slightly abused to refer to the use of said feature, typically to map discrete GPUs to Windows/OSX machines on linux hosts, which allows the user to run GPU-bound tasks in said OSes without the need for a dual-boot setup.

In short, this is what some crazy gamers like me do to play stuff without running Windows baremetal or go through the issues Proton still has.

This, however, is not free of challenges. Virtualization is a complex topic, specially when running latency-sensitive workloads such as gaming, when more than 16ms of time between frames is usually considered unacceptable.

In this article I will explore some of the techniques I have used and tested, which are less known than the usual CPU-pinning, Hyper-V Enlightments, and in general everything covered on the [Archlinux wiki page about VFIO](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF).

I repeat: This article considers the topics covered in the wiki page linked above as the bare minimum. If you intend to use this as a reference for tweaking your own setup, make sure you understand all the strategies discussed there.

And now, let's jump to the action

<!--more-->

## Setup

At the time of writing, my setup consist in the following

| What        | Which                  |
| ----------- | ---------------------- |
| CPU         | Intel i9-9900k         |
| GPU         | Nvidia GTX 1080 Ti     |
| Motherboard | Gigabyte Z390 M Gaming |
| Storage     | 2x Samsung 860 EVO     |

The whole XML confguration for my VM can be found [here](https://gist.github.com/roobre/8f2d86a51a6b619a6622a64a58f9fc94).

*Note*: I'm using ZFS as the storage solution for my home PC, so you will likely see a lot of paths in the XML being referred as block devices under `/dev/zvol/*`. This is actually not important and everything should work the same using raw partitions or `.qcow2` files.

### Note on the number of cores

A few months ago, I was using an i5-6600k for virtualization instead. I do not recommend this, under any circumstance: Most modern games need at least 4 cores to perform decently, so if you have less than 8 cores, you will have little success with vfio, either with the tricks explained here or likely anywhere else.

The main reason for this is that your host still needs to do a lot of stuff while you are running the VM. If you don't reserve enough cores for it, your virtual machine will be preempted out by the linux scheduler, causing huge latency spikes both due to the scheduling itself, and by the hosts tasks evicting their data from the L1 and L2 caches.

## The basics

As I have mentioned before, I will not cover the basic setup of the VM here. You can check the [Archlinux wiki page about VFIO](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF) for that, or one of the multiple guides you'll find on [r/vfio](https://reddit.com/r/vfio) or [Level1Techs](https://forum.level1techs.com/c/software/vfio). However I will list what I currently have just for reference:

### [CPU Pinning](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#CPU_pinning)

 I'm currently mapping 12 of the 16 logical cores my CPU has to the VM, and this ratio is working nicely so far. Just take into account the following:

* `lstopo`: Check your CPU topology, and assign cores with some common sense. Keep multiple threads of the same physical CPU to either the host or the guest. If some of your cores share L2 or L3 caches, try to respect that assignment too, so the same cache is not accessed by both. Failure to do this will cause evictions and poor locality.

![`lstopo`](/img/vfio/lstopo.svg)
<center>*Output of `lstopo` for my machine*</center>

* [emulatorpin](https://gist.github.com/roobre/8f2d86a51a6b619a6622a64a58f9fc94#file-winvirtexpress-xml-L38): Reserve some threads for the emulator (qemu) to run io on them without penalizing the guest.

### [SCREAM](https://github.com/duncanthrax/scream/)

The best solution for audio I know at the time of writing is SCREAM. It's easy to configure, following the author's documentation on their [github page](https://github.com/duncanthrax/scream/).


## Interrupt masking

I have found this to be a nice improvement, not for overall performance but it helps stuttering noticeably.

The two core things to take into account here are:

1. Map vfio-related interrupts to cores assigned to the guest.
2. Map other interrupts to cores assigned to the host.

One can easily see the list of interrupts taking place on a linux OS by `cat`ing `/proc/interrupts`, which typically looks like the following:

```
            CPU0       CPU1       CPU2       CPU3
   0:         20          0          0          0  IR-IO-APIC    2-edge      timer
   1:          0          0          0         33  IR-IO-APIC    1-edge      i8042
   8:          1          0          0          0  IR-IO-APIC    8-edge      rtc0
   9:          0    9612805          0          0  IR-IO-APIC    9-fasteoi   acpi

   [ ... ]
```

The first column is the IRQ number of each interrupt, which we can use to fetch info or change some parameters by inspecting `/proc/irq/$irq_num/`. In order to restrict each interrupt to certain cores, the files we are looking for are `smp_affinity` and its friendlier version, `smp_affinity_list`. The first one will accept an hex-formatted string, which will be interpreted as a bitmap of which cores are allowed to execute the interruption, while the second will do the same but in a friendlier format for humans. Since I'm a human, I prefer to use the second.

I have two snippets which take care of mapping vfio interrupts to vm-pinned cores and non-vfio interrupts to host-reserved cores:

```bash
# Map VFIO interrupts to pinned cores
grep -e vfio /proc/interrupts | cut -d: -f1 | tr -d ' ' | while read int; do
	echo 2-7,10-15 > /proc/irq/$int/smp_affinity_list
done

# Map other interrupts to host cores
grep -e edge /proc/interrupts | cut -d: -f1 | tr -d ' ' | while read int; do
	echo 0-1,8-9 > /proc/irq/$int/smp_affinity_list
done
```

Note that the `grep -e edge` just fitted fine for me, capturing all interrupts that were being fired more or less frequently. YMMV.

### Results

I have tested this using the [Shadow of the Tomb Raider](https://steamcommunity.com/id/roobre/stats/appid/750920/). There are mainly three reasons for it: It is a modern game, showing a real-world load for my use-case (unlike 3D Mark); it saves all the frame times in an easily-parseable csv format; and it is a great game. You should buy it.

No interrupt masking:

[![Figure: Frame times and FPS with uncontrolled interrupt mapping](/img/vfio/time-unmasked.png)](/img/vfio/time-unmasked.svg)

Interrupt masking:

[![Figure: Frame times and FPS with controlled interrupt mapping](/img/vfio/time-masked.png)](/img/vfio/time-masked.svg)

As for the overall performance:

| Percentile | FPS (without masking) | FPS (with masking) |
|------------|-----------------------|--------------------|
| Lowest 1%  | 60.06302429           | 60.9259809         |
| Lowest 2%  | 63.00371762           | 63.52562129        |
| Lowest 5%  | 66.58321581           | 67.29475101        |

As it can be seen, while the performance improvement is not quite significant, dispersion has been reduced by a fair amount, enought for the naked eye to see it.


## CPU Shielding

(WIP)
