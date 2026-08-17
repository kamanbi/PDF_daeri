import 'size_guard.dart';

/// 실패는 예외가 아니라 결과 타입으로 다룬다. 상위 catch 한 줄로 무력화되지 않게 한다.
///
/// 규칙: `lib/pdf/**`와 `lib/core/size_guard.dart`의 공개 API는 예외를 던지지 않는다.
/// 실패는 [PdfErr]로 반환한다. 내부에서 잡은 플랫폼 예외는 [PdfFailure]로 변환해 올린다.
sealed class PdfFailure {
  const PdfFailure();
}

class SourceMissing extends PdfFailure {
  const SourceMissing(this.path);
  final String path;
}

class SourceCorrupted extends PdfFailure {
  const SourceCorrupted(this.path);
  final String path;
}

class SourceEncrypted extends PdfFailure {
  const SourceEncrypted(this.path);
  final String path;
}

class OutOfSpace extends PdfFailure {
  const OutOfSpace(this.requiredBytes);
  final int requiredBytes;
}

class PermissionDenied extends PdfFailure {
  const PermissionDenied(this.detail);
  final String detail;
}

class Cancelled extends PdfFailure {
  const Cancelled();
}

/// 용량 검증 게이트 위반. §4 참조.
class SizeGuardViolation extends PdfFailure {
  const SizeGuardViolation(this.blocked);
  final GuardBlocked blocked;
}

/// 라이브러리가 요구 기능(무손실 페이지 import·리소스 중복 제거 등)을 지원하지 않음.
/// 우회 구현을 만들지 않고 이 값으로 보고한다.
class EngineUnsupported extends PdfFailure {
  const EngineUnsupported(this.capability);
  final String capability;
}

class UnknownFailure extends PdfFailure {
  const UnknownFailure(this.message);
  final String message;
}

/// 공통 결과 타입.
sealed class PdfResult<T> {
  const PdfResult();
}

class PdfOk<T> extends PdfResult<T> {
  const PdfOk(this.value);
  final T value;
}

class PdfErr<T> extends PdfResult<T> {
  const PdfErr(this.failure);
  final PdfFailure failure;
}
