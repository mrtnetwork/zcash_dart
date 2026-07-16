#[cfg(target_arch = "wasm32")]
use std::collections::HashMap;
use std::hash::Hash;

#[cfg(not(target_arch = "wasm32"))]
use dashmap::DashMap;

#[cfg(target_arch = "wasm32")]
use std::sync::RwLock;

pub struct PlatformMap<K, V> {
    #[cfg(not(target_arch = "wasm32"))]
    inner: DashMap<K, V>,

    #[cfg(target_arch = "wasm32")]
    inner: RwLock<HashMap<K, V>>,
}

impl<K: Eq + Hash, V> PlatformMap<K, V> {
    pub fn new() -> Self {
        Self {
            #[cfg(not(target_arch = "wasm32"))]
            inner: DashMap::new(),

            #[cfg(target_arch = "wasm32")]
            inner: RwLock::new(HashMap::new()),
        }
    }

    pub fn insert(&self, k: K, v: V) -> Option<V> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.inner.insert(k, v)
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.inner.write().unwrap().insert(k, v)
        }
    }

    pub fn remove(&self, k: &K) -> Option<V> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.inner.remove(k).map(|(_, v)| v)
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.inner.write().unwrap().remove(k)
        }
    }

    pub fn contains_key(&self, k: &K) -> bool {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.inner.contains_key(k)
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.inner.read().unwrap().contains_key(k)
        }
    }

    pub fn len(&self) -> usize {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.inner.len()
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.inner.read().unwrap().len()
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn clear(&self) {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.inner.clear();
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.inner.write().unwrap().clear();
        }
    }
}

impl<K: Eq + Hash, V: Clone> PlatformMap<K, V> {
    pub fn get(&self, k: &K) -> Option<V> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.inner.get(k).map(|v| v.clone())
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.inner.read().unwrap().get(k).cloned()
        }
    }
}

impl<K: Eq + Hash, V> Default for PlatformMap<K, V> {
    fn default() -> Self {
        Self::new()
    }
}
