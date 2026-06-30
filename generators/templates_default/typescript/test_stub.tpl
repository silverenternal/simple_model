/**
 * Auto-generated test stubs for {{component_name}} (module: {{module_name}}).
 * 每个 todo 对应一条 it()，把 expect(true).toBe(true) 替换为真实断言。
 */
import { describe, it, expect } from "vitest";
import { {{component_name}} } from "./{{snake_name}}";
{{todos_block}}
describe("{{component_name}}", () => {
{{test_functions}}
});
