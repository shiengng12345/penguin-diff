# 第三方依赖与许可证资源

> Rust 根据 Cargo.lock 与 cargo metadata 生成，Swift 根据 Package.resolved 与本机 checkout 登记。历史表列声明；当前[原文资源交付](license-delivery-quality.zh.md)覆盖104组件166份文本，离线校验与包消费者通过，未替代实际链接／法律兼容性和正式发行审核。MCP 引入第三方 Swift 包，最终包静态链接这些依赖，不要求用户安装额外运行时。

## Swift 固定依赖

| 包 | 版本 | 许可证 / 范围 |
| --- | --- | --- |
| modelcontextprotocol/swift-sdk | 0.12.1 | Apache-2.0 / MIT 按贡献适用；LICENSE 明确许可过渡，文档另适用 CC-BY-4.0；本轮仅使用 stdio Server |
| apple/swift-log | 1.15.1 | Apache-2.0；默认 no-op 日志，不记录输入/Token |
| apple/swift-system | 1.8.1 | Apache-2.0；stdio 系统接口 |
| mattt/eventsource | 1.5.1 | MIT；SDK 传递依赖，不开放产品 SSE/远程 MCP |
| apple/swift-nio | 2.103.0 | Apache-2.0；Package.resolved 传递依赖，不开放产品监听端口 |
| apple/swift-collections | 1.7.1 | Apache-2.0；Package.resolved 传递依赖 |
| apple/swift-atomics | 1.3.1 | Apache-2.0；Package.resolved 传递依赖 |

许可证依据为本机已获取的固定版本 LICENSE；是否进入实际最终链接图以构建产物为准。原文资源打包与本机来源完整性已通过；实际链接和发行法律审核仍 OPEN。

## Rust 固定依赖

| Rust 包 | 版本 | 声明许可证 |
| --- | --- | --- |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 |
| arraydeque | 0.5.1 | MIT/Apache-2.0 |
| autocfg | 1.5.1 | Apache-2.0 OR MIT |
| bitflags | 2.13.2 | MIT OR Apache-2.0 |
| bytecount | 0.6.9 | Apache-2.0/MIT |
| castaway | 0.2.4 | MIT |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| compact_str | 0.10.0 | MIT |
| core_detect | 1.0.0 | MIT/Apache-2.0 |
| countme | 3.0.1 | MIT OR Apache-2.0 |
| cow-utils | 0.1.3 | MIT |
| displaydoc | 0.2.7 | MIT OR Apache-2.0 |
| dragonbox_ecma | 0.1.12 | Apache-2.0 WITH LLVM-exception OR BSL-1.0 |
| encoding_rs | 0.8.42 | (Apache-2.0 OR MIT) AND BSD-3-Clause |
| fastrand | 2.5.0 | Apache-2.0 OR MIT |
| foldhash | 0.2.0 | Zlib |
| hashbrown | 0.14.5 | MIT OR Apache-2.0 |
| hashbrown | 0.16.1 | MIT OR Apache-2.0 |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 |
| hashlink | 0.11.1 | MIT OR Apache-2.0 |
| icu_collections | 2.3.0 | Unicode-3.0 |
| icu_locale_core | 2.3.0 | Unicode-3.0 |
| icu_locale_fallback | 2.3.0 | Unicode-3.0 |
| icu_locale_fallback_data | 2.3.0 | Unicode-3.0 |
| icu_provider | 2.3.1 | Unicode-3.0 |
| icu_segmenter | 2.3.0 | Unicode-3.0 |
| icu_segmenter_data | 2.3.0 | Unicode-3.0 |
| itoa | 1.0.18 | MIT OR Apache-2.0 |
| litemap | 0.8.3 | Unicode-3.0 |
| memchr | 2.8.3 | Unlicense OR MIT |
| multiversion_no_op | 1.0.0 | Apache-2.0 OR MIT |
| nonmax | 0.5.5 | MIT OR Apache-2.0 |
| num-bigint | 0.5.1 | MIT OR Apache-2.0 |
| num-integer | 0.1.47 | MIT OR Apache-2.0 |
| num-traits | 0.2.19 | MIT OR Apache-2.0 |
| oxc_allocator | 0.152.0 | MIT |
| oxc_ast | 0.152.0 | MIT |
| oxc_ast_macros | 0.152.0 | MIT |
| oxc_data_structures | 0.152.0 | MIT |
| oxc_diagnostics | 0.152.0 | MIT |
| oxc_ecmascript | 0.152.0 | MIT |
| oxc_estree | 0.152.0 | MIT |
| oxc_index | 5.0.0 | MIT |
| oxc_parser | 0.152.0 | MIT |
| oxc_regular_expression | 0.152.0 | MIT |
| oxc_span | 0.152.0 | MIT |
| oxc_str | 0.152.0 | MIT |
| oxc_syntax | 0.152.0 | MIT |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 |
| phf | 0.14.0 | MIT |
| phf_generator | 0.14.0 | MIT |
| phf_macros | 0.14.0 | MIT |
| phf_shared | 0.14.0 | MIT |
| potential_utf | 0.1.6 | Unicode-3.0 |
| pretty_yaml | 0.6.0 | MIT |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 |
| quote | 1.0.47 | MIT OR Apache-2.0 |
| rowan | 0.16.1 | MIT OR Apache-2.0 |
| rustc-hash | 1.1.0 | Apache-2.0/MIT |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT |
| rustversion | 1.0.23 | MIT OR Apache-2.0 |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 |
| seq-macro | 0.3.6 | MIT OR Apache-2.0 |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 |
| serde_json | 1.0.151 | MIT OR Apache-2.0 |
| simdutf8 | 0.1.5 | MIT OR Apache-2.0 |
| siphasher | 1.0.4 | MIT OR Apache-2.0 |
| smallvec | 1.16.2 | MIT OR Apache-2.0 |
| smawk | 0.3.3 | MIT |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 |
| syn | 2.0.119 | MIT OR Apache-2.0 |
| syn | 3.0.6 | MIT OR Apache-2.0 |
| synstructure | 0.14.0 | MIT |
| text-size | 1.1.1 | MIT OR Apache-2.0 |
| textwrap | 0.16.4 | MIT |
| tiny_pretty | 0.2.1 | MIT |
| tinystr | 0.8.4 | Unicode-3.0 |
| unicode-id-start | 1.5.0 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| unicode-ident | 1.0.26 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| unicode-segmentation | 1.13.3 | MIT OR Apache-2.0 |
| unicode-width | 0.2.2 | MIT OR Apache-2.0 |
| utf8_iter | 1.0.4 | Apache-2.0 OR MIT |
| winnow | 0.7.15 | MIT |
| writeable | 0.6.4 | Unicode-3.0 |
| yaml-rust2 | 0.11.1 | MIT OR Apache-2.0 |
| yaml_parser | 0.3.0 | MIT |
| yoke | 0.8.3 | Unicode-3.0 |
| yoke-derive | 0.8.4 | Unicode-3.0 |
| zerofrom | 0.1.8 | Unicode-3.0 |
| zerofrom-derive | 0.1.8 | Unicode-3.0 |
| zerotrie | 0.2.5 | Unicode-3.0 |
| zerovec | 0.11.8 | Unicode-3.0 |
| zerovec-derive | 0.11.6 | Unicode-3.0 |
| zmij | 1.0.23 | MIT |
