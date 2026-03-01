/*
 * Minimal PID-1 init: spin forever.
 *
 * Compiled with -nostdlib so we define _start directly.
 * 'naked' suppresses prologue/epilogue so the linker sees _start
 * as a genuine ELF entry-point symbol.
 */
void __attribute__((naked, noreturn)) _start(void)
{
    __asm__("1: j 1b");
}
