"""Auto-generated base — do not edit, rerun bootstrap.sh"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Type


@dataclass
class Service(ABC):
    """所有 component 的抽象基类"""
    name: str = ""
    exports: List[str] = field(default_factory=list)
    imports: List[str] = field(default_factory=list)
    optional: bool = False

    @abstractmethod
    def __call__(self) -> Any:
        raise NotImplementedError(f"{self.__class__.__name__}.__call__() 未实现")


class Registry:
    _r: Dict[str, Type[Service]] = {}
    @classmethod
    def register(cls, c): cls._r[c.name] = c; return c
    @classmethod
    def get(cls, n): return cls._r.get(n)
    @classmethod
    def all(cls): return dict(cls._r)
