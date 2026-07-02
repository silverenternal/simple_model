[package]
name = "{{crate_name}}"
version = "0.1.0"
edition = "2021"

[lib]
name = "{{crate_name}}"
path = "src/lib.rs"

[dependencies]
serde = { version = "1", features = ["derive"] }
