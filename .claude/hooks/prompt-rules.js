// UserPromptSubmit: CLAUDE.md is read once at session start and drifts out of reach as the
// conversation grows. This rides along with every prompt to keep it in front of the model.
console.log(
  "<session-rules>\n" +
    "`CLAUDE.md`는 절대규칙이다. 읽는 것으로 끝내지 말고 따를 것. 어기는 일은 없어야 한다.\n" +
    "</session-rules>"
);
