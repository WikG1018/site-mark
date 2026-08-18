import hilog from '@ohos.hilog';

@Entry
@Component
struct Index {
  aboutToAppear() {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility index aboutToAppear');
  }
 @State message: string = 'Hello World'
   build() {
         Row() {
           Column() {
             Text(this.message)
               .fontSize(50)
               .fontWeight(FontWeight.Bold)
           }
             .width('100%')
         }
             .height('100%')
   }
 }
