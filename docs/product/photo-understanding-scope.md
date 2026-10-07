# Ordinary-photo understanding: proposed first scope

Status: scoped on 2026-10-07; no new weights, SDK install, phone evaluation or production vision integration performed.

## User-visible capability

Start with direct questions about one explicitly selected photo in the current chat: describe visible objects, colors, simple counts and spatial relationships; read visible text; explain a screenshot. The first slice should answer the user's question about pixels, not merely run OCR or save a searchable caption.

Use the existing paperclip entry point. Present a thumbnail with a remove action and make the visual question scope explicit. Do not silently index a generated description as Knowledge Base evidence. OCR document imports continue to use their existing extraction/indexing path. Image answers must be identified as model interpretations and preserve a reference to the original selected image.

Retain the selected image locally with that chat only if the owner accepts this retention design; deleting the chat or erasing all data then removes it. Turn provenance should record the image identity, preprocessing version and model/runtime identity. Regeneration must use the original turn's image scope. There is no cross-chat image memory.

A text-only selection, including the current Qwen model, must explain the unsupported input and offer an explicit model switch only when an eligible image model exists. Do not silently switch providers or send images to any remote service.

## Recommended evaluation route

Investigate Apple's on-device image prompting first. Apple's current [multimodal prompting documentation](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting) describes image attachments with text prompts. This is API evidence, not a guarantee of image eligibility or quality on the owner's phone. The scope excludes Private Cloud Compute even where Apple's examples discuss it.

Local toolchain rechecked on 2026-10-07: Xcode 26.6, iPhoneOS SDK 26.5. The prior device observation is iOS 27.0; no new phone query was made. The installed SDK does not expose the new image Attachment API. A compatible SDK/toolchain and runtime capability probe are the next prerequisites, not another OS update or model download by default. Installing/changing Xcode is outside this scope and needs a separately agreed task, with disk space resolved first.

Retain downloadable vision as an alternative if native eligibility or quality fails. Existing [SmolVLM results](../../experiments/local_vision/RESULTS-2026-10-06.md) include a fabricated absent salary. [Liquid results](../../experiments/local_vision/LIQUID-RESULTS-2026-10-06.md) establish Mac compatibility on three known cases, not an accuracy advantage or phone qualification; visual-token cost and licensing remain unresolved. Both vision pairs were already removed after evaluation. Re-downloads are not part of this scope.

## Bounded quality and device gate

Before implementation, freeze a small held-out set of 24 fictional, owned or consented images/questions:

- Eight ordinary-image questions across objects, colors, counts and spatial relationships.
- Four screenshots or document photos, including exact visible text.
- Four orientation/blur/low-light cases; require uncertainty when details are unreadable.
- Eight deliberately unanswerable or adversarial cases, including absent salary, hidden details and instruction-like text inside the image.

Record expected facts and acceptable uncertainty before running. Proposed advancement criteria: at least 14 of 16 answerable cases factually correct, all eight unanswerable/adversarial cases avoid invented details or obeying embedded instructions, and no unsupported certainty on degraded inputs. These are proposed screening thresholds, not a product rating or general reliability claim. Preserve exact prompts/outputs; do not tune against the held-out answers and reuse them as fresh evidence.

Use an isolated on-device probe after agreeing the toolchain and phone run. Verify airplane-mode operation, HEIC orientation/color handling, bounded image resolution/token use, cancellation during preprocessing and generation, background interruption, return-to-app behavior, memory and repeated-run thermals. Record latency with preprocessing included. No public speed, memory or battery rating follows from a few successful examples.

Only after both quality and device gates pass should production work add the image-input seam, retained-image lifecycle, provenance migration and capability icon. Knowledge Base reasoning from visual observations remains a separate scope and must preserve fail-closed evidence behavior.

## Decisions to agree next

1. Approve native Apple eligibility/toolchain investigation as the first route, including a disk plan before any installation.
2. Confirm one-image direct questions and chat-local image retention as the first product slice.
3. Agree the frozen screening set and advancement thresholds before a device run.
