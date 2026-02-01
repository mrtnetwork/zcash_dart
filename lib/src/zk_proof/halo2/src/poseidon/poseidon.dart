import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class Pow5Config {
  final List<Column<Advice>> state;
  final Column<Advice> partialSbox;
  final List<Column<Fixed>> rcA;
  final List<Column<Fixed>> rcB;
  final Selector sFull;
  final Selector sPartial;
  final Selector sPadAndAdd;

  final int halfFullRounds;
  final int halfPartialRounds;
  final BigInt alpha; // length 4
  final List<List<PallasNativeFp>> roundConstants;
  final List<List<PallasNativeFp>> mReg;
  final P128Pow5T3NativeFp spec;

  const Pow5Config(
      {required this.state,
      required this.partialSbox,
      required this.rcA,
      required this.rcB,
      required this.sFull,
      required this.sPartial,
      required this.sPadAndAdd,
      required this.halfFullRounds,
      required this.halfPartialRounds,
      required this.alpha,
      required this.roundConstants,
      required this.mReg,
      required this.spec});
  static Pow5Config configure(
      {required ConstraintSystem meta,
      required List<Column<Advice>> state,
      required Column<Advice> partialSbox,
      required List<Column<Fixed>> rcA,
      required List<Column<Fixed>> rcB,
      required P128Pow5T3NativeFp spec}) {
    final int width = spec.width();
    final int rate = spec.rate();

    final halfFullRounds = spec.fullRounds() ~/ 2;
    final halfPartialRounds = spec.partialRounds() ~/ 2;

    final (roundConstants, mReg, mInv) =
        (spec.constants.constants, spec.constants.mds, spec.constants.mdsInv);

    for (final column in [...state, ...rcB]) {
      meta.enableEquality(column);
    }

    final sFull = meta.selector();
    final sPartial = meta.selector();
    final sPadAndAdd = meta.selector();

    Expression pow5(Expression v) {
      final v2 = v * v;
      return v2 * v2 * v;
    }

    // ---------------- Full rounds ----------------
    meta.createGate((meta) {
      final s = meta.querySelector(sFull);

      return Constraints(
        selector: s,
        constraints: List.generate(width, (nextIdx) {
          final stateNext = meta.queryAdvice(state[nextIdx], Rotation.next());

          final expr = List.generate(width, (idx) {
            final stateCur = meta.queryAdvice(state[idx], Rotation.cur());
            final rc = meta.queryFixed(rcA[idx]);
            return pow5(stateCur + rc) * mReg[nextIdx][idx];
          }).reduce((a, b) => a + b);

          return expr - stateNext;
        }),
      );
    });

    // ---------------- Partial rounds ----------------
    meta.createGate((meta) {
      final cur0 = meta.queryAdvice(state[0], Rotation.cur());
      final mid0 = meta.queryAdvice(partialSbox, Rotation.cur());

      final rcA0 = meta.queryFixed(rcA[0]);
      final rcB0 = meta.queryFixed(rcB[0]);

      final s = meta.querySelector(sPartial);

      Expression mid(int idx) {
        var acc = mid0 * mReg[idx][0];
        for (var i = 1; i < width; i++) {
          final cur = meta.queryAdvice(state[i], Rotation.cur());
          final rc = meta.queryFixed(rcA[i]);
          acc += (cur + rc) * mReg[idx][i];
        }
        return acc;
      }

      Expression next(int idx) {
        return List.generate(width, (j) {
          final next = meta.queryAdvice(state[j], Rotation.next());
          return next * mInv[idx][j];
        }).reduce((a, b) => a + b);
      }

      Expression partialLinear(int idx) {
        final rc = meta.queryFixed(rcB[idx]);
        return mid(idx) + rc - next(idx);
      }

      return Constraints(
        selector: s,
        constraints: [
          pow5(cur0 + rcA0) - mid0,
          pow5(mid(0) + rcB0) - next(0),
          for (var i = 1; i < width; i++) partialLinear(i),
        ],
      );
    });

    // ---------------- Pad and add ----------------
    meta.createGate((meta) {
      final initialRate = meta.queryAdvice(state[rate], Rotation.prev());
      final outputRate = meta.queryAdvice(state[rate], Rotation.next());

      final s = meta.querySelector(sPadAndAdd);

      Expression padAndAdd(int idx) {
        final initial = meta.queryAdvice(state[idx], Rotation.prev());
        final input = meta.queryAdvice(state[idx], Rotation.cur());
        final output = meta.queryAdvice(state[idx], Rotation.next());
        return initial + input - output;
      }

      return Constraints(
        selector: s,
        constraints: [
          for (var i = 0; i < rate; i++) padAndAdd(i),
          initialRate - outputRate
        ],
      );
    });

    return Pow5Config(
        state: state,
        partialSbox: partialSbox,
        rcA: rcA,
        rcB: rcB,
        sFull: sFull,
        sPartial: sPartial,
        sPadAndAdd: sPadAndAdd,
        halfFullRounds: halfFullRounds,
        halfPartialRounds: halfPartialRounds,
        alpha: BigInt.from(5),
        roundConstants: roundConstants,
        spec: spec,
        mReg: mReg);
  }

  List<PoseidonStateWord> initialState(Layouter layouter) {
    final List<PoseidonStateWord> state = layouter.assignRegion(
      (Region region) {
        final rate = spec.rate();
        final List<PoseidonStateWord> words = [];

        void loadStateWord(int i, PallasNativeFp value) {
          final AssignedCell<PallasNativeFp> v =
              region.assignAdviceFromConstant(this.state[i], 0, value);
          words.add(PoseidonStateWord(v));
        }

        for (int i = 0; i < rate; i++) {
          loadStateWord(i, PallasNativeFp.zero());
        }
        loadStateWord(rate, PallasNativeFp(BigInt.two << 64));

        return words;
      },
    );
    if (state.length != spec.width()) {
      throw Halo2Exception.operationFailed("initialState",
          reason: "Invalid state width.");
    }

    return state;
  }

  List<PoseidonStateWord> addInput(
    Layouter layouter,
    List<PoseidonStateWord> initialState,
    Absorbing<PaddedWord> input,
  ) {
    return layouter.assignRegion(
      (Region region) {
        // Enable padding-and-add selector at offset 1
        sPadAndAdd.enable(region: region, offset: 1);

        // ---- Load initial state ----
        final List<PoseidonStateWord> loadedInitialState =
            List.generate(spec.width(), (i) {
          final varCell = initialState[i].inner.copyAdvice(region, state[i], 0);
          return PoseidonStateWord(varCell);
        });

        // ---- Load input words ----
        final List<PoseidonStateWord> loadedInput = [];

        final exposed = input.exposeInner();
        for (var i = 0; i < exposed.length; i++) {
          final padded = exposed[i];

          if (padded == null) {
            throw Halo2Exception.operationFailed("addInput",
                reason: "Input is not padded.");
          }

          late final Cell cell;
          late final PallasNativeFp? value;
          switch (padded) {
            case final PaddedWordMessage r:
              cell = r.inner.cell;
              value = r.inner.value;
              break;
            case final PaddedWordPadding r:
              value = r.inner;
              cell = region.assignFixed(rcB[i], 1, () => value).cell;
              break;
          }
          final varCell = region.assignAdvice(state[i], 1, () => value);

          region.constrainEqual(cell, varCell.cell);

          loadedInput.add(PoseidonStateWord(varCell));
        }

        // ---- Constrain output ----
        final List<PoseidonStateWord> output = List.generate(spec.width(), (i) {
          PallasNativeFp? value;
          if (loadedInitialState[i].inner.hasValue) {
            value = loadedInitialState[i].inner.getValue();
            if (i < loadedInput.length) {
              if (loadedInput[i].inner.hasValue) {
                value += loadedInput[i].inner.getValue();
              }
            }
          }
          final varCell = region.assignAdvice(state[i], 2, () => value);

          return PoseidonStateWord(varCell);
        });
        return output;
      },
    );
  }

  Squeezing<PoseidonStateWord> getOutput(List<PoseidonStateWord> word) {
    return Squeezing(List<PoseidonStateWord?>.from(word.sublist(0, 2)));
  }

  List<PoseidonStateWord> permute(
      Layouter layouter, List<PoseidonStateWord> initialState) {
    return layouter.assignRegion(
      (Region region) {
        // Load the initial state
        Pow5State state = Pow5State.load(region, initialState, this);
        // First half of full rounds
        for (int i = 0; i < halfFullRounds; i++) {
          state = state.fullRound(region, i, i, this);
        }
        // Partial rounds
        for (var r = 0; r < halfPartialRounds; r++) {
          state = state.partialRound(
              region, this, halfFullRounds + 2 * r, halfFullRounds + r);
        }
        // Second half of full rounds
        for (var r = 0; r < halfFullRounds; r++) {
          state = state.fullRound(
              region,
              halfFullRounds + 2 * halfPartialRounds + r,
              halfFullRounds + halfPartialRounds + r,
              this);
        }
        // Extract final state
        return state.words;
      },
    );
  }
}

class Pow5State {
  final List<PoseidonStateWord> words;
  const Pow5State(this.words);

  factory Pow5State.load(
      Region region, List<PoseidonStateWord> initialState, Pow5Config config) {
    final List<PoseidonStateWord> words = List<PoseidonStateWord>.generate(
      config.spec.width(),
      (index) => PoseidonStateWord(
          initialState[index].inner.copyAdvice(region, config.state[index], 0)),
    );
    return Pow5State(words);
  }
  factory Pow5State.round(
      Region region,
      int round,
      int offset,
      Selector roundGate,
      Pow5Config config,
      (
        int,
        List<PallasNativeFp?>,
      )
              Function(Region)
          roundFn) {
    // Enable the required gate
    roundGate.enable(region: region, offset: offset);

    // Load round constants
    for (var i = 0; i < config.spec.width(); i++) {
      region.assignFixed(
          config.rcA[i], offset, () => config.roundConstants[round][i]);
    }

    // Compute next round state
    final result = roundFn(region);
    final List<PallasNativeFp?> nextState = result.$2;

    // Assign next state words
    final List<PoseidonStateWord> state = List<PoseidonStateWord>.generate(
        config.spec.width(),
        (index) => PoseidonStateWord(region.assignAdvice(
            config.state[index], offset + 1, () => nextState[index])));
    return Pow5State(state);
  }

  Pow5State fullRound(Region region, int round, int offset, Pow5Config config) {
    return Pow5State.round(
      region,
      round,
      offset,
      config.sFull,
      config,
      (Region region) {
        // q_i = state_i + round_constants[round][i]
        final List<PallasNativeFp?> q = List<PallasNativeFp?>.generate(
          words.length,
          (index) {
            final word = words[index];
            final c = config.roundConstants[round][index];
            if (word.inner.hasValue) {
              return word.inner.getValue() + c;
            }
            return null;
          },
        );
        // r_i = q_i ^ alpha
        final List<PallasNativeFp?> r = List.generate(
          q.length,
          (index) {
            if (q[index] != null) {
              return q[index]!.pow(config.alpha);
            }
            return q[index];
          },
        );
        final List<PallasNativeFp?> nextState = List<PallasNativeFp?>.generate(
          config.spec.width(),
          (index) {
            final mI = config.mReg[index];
            PallasNativeFp acc = PallasNativeFp.zero();
            for (final i in r.indexed) {
              if (i.$2 == null) return null;
              acc = (acc + mI[i.$1] * i.$2!);
            }
            return acc;
          },
        );
        return (round + 1, nextState);
      },
    );
  }

  Pow5State partialRound(
      Region region, Pow5Config config, int round, int offset) {
    return Pow5State.round(
      region,
      round,
      offset,
      config.sPartial,
      config,
      (Region region) {
        // final m = config.mReg;

        // p = current state values
        final List<PallasNativeFp?> p =
            words.map((e) => e.inner.value).toList();
        List<PallasNativeFp?>? r;
        if ((p[0] != null)) {
          final r0 =
              (p[0]! + config.roundConstants[round][0]).pow(config.alpha);
          final rI = p.sublist(1).indexed.map((e) {
            if (e.$2 == null) return null;
            return e.$2! + config.roundConstants[round][e.$1 + 1];
          });
          r = [r0, ...rI];
        }
        // Constrain partial S-box output (r[0])
        region.assignAdvice(config.partialSbox, offset, () => r?[0]);
        List<PallasNativeFp?> pMid = config.mReg.map<PallasNativeFp?>((mi) {
          if (r != null) {
            PallasNativeFp acc = PallasNativeFp.zero();
            for (final miJ in mi.indexed) {
              final rJ = r[miJ.$1];
              if (rJ == null) return null;
              acc = acc + miJ.$2 * rJ;
            }
            return acc;
          }
          return null;
        }).toList();
        for (int i = 0; i < config.spec.width(); i++) {
          region.assignFixed(
            config.rcB[i],
            offset,
            () {
              return config.roundConstants[round + 1][i];
            },
          );
        }

        List<PallasNativeFp?>? rMid;
        if ((pMid[0] != null)) {
          final r0 = (pMid[0]! + config.roundConstants[round + 1][0])
              .pow(config.alpha);
          final rI = pMid.sublist(1).indexed.map((e) {
            if (e.$2 == null) return null;
            return e.$2! + config.roundConstants[round + 1][e.$1 + 1];
          });
          rMid = [r0, ...rI];
        }
        List<PallasNativeFp?> state = config.mReg.map<PallasNativeFp?>((mi) {
          PallasNativeFp acc = PallasNativeFp.zero();
          if (rMid != null) {
            for (final miJ in mi.indexed) {
              final rJ = rMid[miJ.$1];
              if (rJ == null) return null;
              acc = acc + miJ.$2 * rJ;
            }
            return acc;
          }
          return null;
        }).toList();

        return (round + 2, state);
      },
    );
  }
}

sealed class PaddedWord {
  const PaddedWord();
}

class PaddedWordMessage extends PaddedWord {
  final AssignedCell<PallasNativeFp> inner;
  const PaddedWordMessage(this.inner);
}

class PaddedWordPadding extends PaddedWord {
  final PallasNativeFp inner;
  const PaddedWordPadding(this.inner);
}

class PoseidonStateWord {
  final AssignedCell<PallasNativeFp> inner;
  const PoseidonStateWord(this.inner);
}

abstract class Sponge<F extends Object, MODE extends SpongeMode<F>> {
  final Pow5Config chip;
  MODE _mode;
  MODE get mode => _mode;
  final List<PoseidonStateWord> state;
  Sponge(this.chip, MODE mode, this.state) : _mode = mode;

  Squeezing<PoseidonStateWord> poseidonSponge(Layouter layouter,
      List<PoseidonStateWord> state, Absorbing<PaddedWord>? input) {
    if (input != null) {
      state = chip.addInput(layouter, state, input);
    }
    state = chip.permute(layouter, state);
    return chip.getOutput(state);
  }
}

class SpongeAbsorbing extends Sponge<PaddedWord, Absorbing<PaddedWord>> {
  SpongeAbsorbing(super.chip, super.mode, super.state);
  factory SpongeAbsorbing.init(Layouter layouter, Pow5Config chip) {
    final state = chip.initialState(layouter);
    return SpongeAbsorbing(chip,
        Absorbing<PaddedWord>(List.filled(chip.spec.rate(), null)), state);
  }
  SpongeSqueezing finishAbsorbing(Layouter layouter) {
    final mode = poseidonSponge(layouter, state, this.mode);
    return SpongeSqueezing(chip, mode, state);
  }

  /// Absorbs an element into the sponge.
  void absorb(Layouter layouter, PaddedWord value) {
    PaddedWord remaining;
    try {
      remaining = mode.absorb(value);
      return;
    } on PoseidonException {
      remaining = value;
    }
    // We've already absorbed as many elements as we can, so apply the sponge
    poseidonSponge(layouter, state, mode);

    // Reset absorbing mode
    _mode = Absorbing<PaddedWord>(List.filled(chip.spec.rate(), null));

    // Now absorption must succeed
    try {
      mode.absorb(remaining);
    } on PoseidonException {
      throw Halo2Exception.operationFailed("absorb",
          reason: "state is not full.");
    }
  }
}

class SpongeSqueezing
    extends Sponge<PoseidonStateWord, Squeezing<PoseidonStateWord>> {
  SpongeSqueezing(super.chip, super.mode, super.state);

  AssignedCell<PallasNativeFp> squeeze(Layouter layouter) {
    PoseidonStateWord? value = mode.squeeze();
    while (value == null) {
      _mode = poseidonSponge(layouter, state, null);
      value = mode.squeeze();
    }
    return value.inner;
  }
}

class HaloPoseidonHash {
  final SpongeAbsorbing sponge;
  const HaloPoseidonHash(this.sponge);
  factory HaloPoseidonHash.init(Layouter layouter, Pow5Config chip) {
    return HaloPoseidonHash(SpongeAbsorbing.init(layouter, chip));
  }
  List<PallasNativeFp> padding(int inputLen) {
    final rate = sponge.chip.spec.rate();
    if (inputLen != rate) {
      throw Halo2Exception.operationFailed("HaloPoseidonHash",
          reason: "Input length must match domain length.");
    }
    final zero = PallasNativeFp.zero();
    final k = ((rate + rate - 1) ~/ rate);
    final padLen = k * rate - rate;
    return List<PallasNativeFp>.filled(padLen, zero);
  }

  AssignedCell<PallasNativeFp> hash(
      Layouter layouter, List<AssignedCell<PallasNativeFp>> messages) {
    final words = messages.map((e) => PaddedWordMessage(e)).toList();
    final message = [
      ...words,
      ...padding(messages.length).map((e) => PaddedWordPadding(e))
    ];
    for (final (_, msg) in message.indexed) {
      sponge.absorb(layouter, msg);
    }
    return sponge.finishAbsorbing(layouter).squeeze(layouter);
  }
}
