//! Auto-generated test stubs for {{component_name}} (module: {{module_name}}).
//! 每个 todo 对应一条 #[test]，把 unimplemented!() 替换为真实断言。

#[cfg(test)]
mod {{component_name | to_snake}}_tests {
    use super::{{snake_name}}::{{component_name}};
{{todos_block}}
{{test_functions}}
}
