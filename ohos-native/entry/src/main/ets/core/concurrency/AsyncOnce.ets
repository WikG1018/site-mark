export type AsyncOnceFactory<T> = () => Promise<T>;

export class AsyncOnce<T> {
  private inFlight: Promise<T> | null = null;
  private generation: number = 0;

  run(factory: AsyncOnceFactory<T>): Promise<T> {
    if (this.inFlight !== null) {
      return this.inFlight;
    }
    const generation = this.generation + 1;
    this.generation = generation;
    const task = this.execute(generation, factory);
    this.inFlight = task;
    return task;
  }

  private async execute(generation: number, factory: AsyncOnceFactory<T>): Promise<T> {
    try {
      return await factory();
    } finally {
      if (generation === this.generation) {
        this.inFlight = null;
      }
    }
  }
}
