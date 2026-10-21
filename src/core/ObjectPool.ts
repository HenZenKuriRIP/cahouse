// Generic free-list pool (projectiles, particles, DOM float texts).
export class ObjectPool<T> {
  private free: T[] = [];
  created = 0;
  constructor(private make: () => T) {}
  get(): T { const o = this.free.pop(); if (o) return o; this.created++; return this.make(); }
  release(o: T): void { this.free.push(o); }
  get available(): number { return this.free.length; }
}
