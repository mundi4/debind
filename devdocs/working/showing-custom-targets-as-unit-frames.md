# 커스텀 대상을 개체창으로 띄우기 (2026-09-28 시작)

> 상태: **계획만 있고 착수 전이다. 실험 기능으로 낸다** (소유자, 2026-09-28). 1절은 소유자가 정했고,
> 2절은 그것을 코드에 옮길 방법, 3절은 착수 전에 확인할 것이다.
>
> 쓴 세션: `debind-92`, 세션 ID `0230bc1c-2732-4a64-9239-bb0fa97e7259`.

지금 `custom1`과 `custom2`는 유닛 참조로만 존재한다. 누구를 가리키는지는 지정할 때 채팅 한 줄로만
보이고, 그 뒤로는 화면에 아무것도 남지 않는다. 그런데 restricted environment 안에서는 전투 중에도
protected 프레임의 `SetAttribute`가 통한다(`RestrictedFrames.lua`, `HANDLE:SetAttribute`와
`GetHandleFrame`). 그러니 우리 unit 버튼 하나가 커스텀 대상을 따라가게 만들 수 있다.

## 1. 정한 것 (소유자, 2026-09-28)

1. **실험 기능으로 낸다.** 켜는 설정에 experimental 딱지를 붙인다.
2. **모양은 아레나 창의 줄 하나다.** `CompactArenaFrame`의 각 줄이 쓰는 `CompactUnitFrameTemplate`
   본체만 가져온다. 여기에는 체력바, 이름, 버프가 들어 있다.
3. **아레나 부품은 이번에 붙이지 않는다.** 디버프 아이콘, 시전바, CC 해제 장신구, 점감 표시가 여기에
   해당한다. 이유는 아직 필요하지 않다는 것이다(소유자). 붙이게 되면 전투 중에도 할 수 있다는 것은
   확인해 두었다. 부품은 모두 protected가 아닌 평범한 프레임이고, 각자의 `SetUnit`은 이벤트 등록과
   값 저장만 한다. 그래서 `arenaN`일 때만 보이게 하는 식으로 유닛에 따라 모양을 바꿀 수 있다. 본체
   크기는 protected라서 restricted environment에서 handle로 바꾼다. 디버프 아이콘에는 블리자드 스스로
   "지금은 안 될 수 있다"는 TODO를 달아 두었다(`ArenaUnitFrameDebuffMixin:Update`).
4. **버프는 템플릿이 그리는 대로 둔다.** secret 값은 블리자드 API가 처리한다. 우리는 보여 주기만 하고,
   그 값으로 무엇을 판단하지는 않는다.

## 2. 구조

### 2.1 유닛은 driver의 `SetUnit`에서 쓴다

`unitMap[alias]`가 바뀌는 길은 둘이다. 이름으로 따라가는 header 자식이 옮겨 갈 때(`CheckUnits`)와
토큰을 직접 지정할 때(`UnitWatch`의 `_onattributechanged`)다. 둘 다 `debind_driver:RunAttribute("SetUnit",
alias, unit)`을 거친다. 그리고 그 `SetUnit`(`SecureBindings.lua`)은 이미 `DelegateFrames[alias]`에
`SetAttribute("unit", unit or "raid41")`을 한다. 우리 창도 frame ref로 넘겨 두고 같은 자리에서
`unit`을 쓴다. 비었을 때는 delegate와 같이 `raid41`을 넣고, 창은 2.3에 따라 숨는다.

### 2.2 표시는 `CompactUnitFrame_SetUnit` 없이 갱신한다

`CompactUnitFrame_SetUnit`은 속성을 두 번 쓴다. `SetAttribute("unit")`과 `SecureUnitButton_OnLoad`다.
우리 비보안 코드가 전투 중에 이것을 부르면 호출이 막힌다. 그러나 두 줄 모두 다른 곳에서 이미
처리된다.

- `unit`은 2.1이 restricted environment에서 쓴다.
- `SecureUnitButton_OnLoad`가 하는 나머지 일(클릭 등록, `*type1`, `*type2`, `menu-function`)은 유닛에
  따라 바뀌지 않는다. 창을 만들 때 전투 밖에서 한 번만 한다.

그래서 창의 비보안 `OnAttributeChanged`가 `unit`을 받아 그 함수 본문에서 두 줄을 뺀 나머지를
수행한다. `frame.unit`과 `displayedUnit`을 넣고, `CompactUnitFrame_RegisterEvents`와
`CompactUnitFrame_UpdateAll`을 부르는 식이다.

### 2.3 보이고 숨는 것은 `RegisterUnitWatch`

유닛이 없거나 `raid41`이면 전투 중에도 알아서 숨는다.

### 2.4 클릭 캐스팅은 직접 등록한다

`FrameRegistry`가 개체창을 알아보는 길목(`SecureUnitButton_OnLoad`, `RegisterUnitWatch` 등)은 남의
창을 위한 것이다. 우리 창은 만들 때 직접 등록한다.

### 2.5 위치

드래그로 옮기고 저장한다. `EditModeArenaUnitFrameSystemTemplate`은 블리자드 편집 모드 시스템이라
상속하지 않는다. 전투 중에는 옮길 수 없다.

## 3. 착수 전에 확인할 것

1. **2.2가 막히지 않는지.** `CompactUnitFrame_UpdateAll`, `CompactUnitFrame_RegisterEvents`,
   `UpdatePrivateAuras` 아래에 protected 호출이 더 있으면 전투 중 갱신이 거기서 막힌다.
2. **템플릿이 요구하는 초기화.** 블리자드 창은 `CompactUnitFrame_SetUpFrame`에 설정 표를 넘겨 준비한다.
   우리 창이 무엇을 넘겨야 하는지 확인한다.

## 4. 테스트

화면 쪽이라 헤드리스 spec은 닿지 않는다. `/debtest`에 등록할 것은 다음과 같다.

- 전투 중에 `custom1`을 지정하면 창의 `unit`이 `unitMap["custom1"]`과 같아진다.
- 이름으로 따라가는 대상은 로스터가 바뀐 뒤에도 창이 같은 사람을 가리킨다.
- 대상을 지우면 창이 숨는다.
