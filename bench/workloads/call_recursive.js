// Recursion, which also exercises the frame stack growth path.
function fib(n) {
  if (n < 2) {
    return n;
  }
  return fib(n - 1) + fib(n - 2);
}
fib(16);
