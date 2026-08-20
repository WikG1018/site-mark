import { describe, expect, it } from '@ohos/hypium';
import { ImagePipelineFailure, UnavailableImagePipeline } from
  '../main/ets/core/media/ImagePipeline';

export default function imagePipelineTest(): void {
  describe('ImagePipeline', () => {
    it('reports a visible degraded state instead of silently copying an unwatermarked image', 0, async () => {
      const pipeline = new UnavailableImagePipeline('native module unavailable');
      expect(pipeline.isDegraded).assertTrue();
      let failure = '';
      try {
        await pipeline.sha256('/missing.jpg');
      } catch (error) {
        failure = (error as ImagePipelineFailure).message;
      }
      expect(failure.startsWith('invalid_data:')).assertTrue();
    });
  });
}
