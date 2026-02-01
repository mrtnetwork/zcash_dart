import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';

class AddConfig {
  final Selector qAdd;

  // lambda
  final Column<Advice> lambda;

  // x-coordinate of P in P + Q = R
  final Column<Advice> xP;

  // y-coordinate of P in P + Q = R
  final Column<Advice> yP;

  // x-coordinate of Q or R in P + Q = R
  final Column<Advice> xQr;

  // y-coordinate of Q or R in P + Q = R
  final Column<Advice> yQr;

  // α = inv0(x_q - x_p)
  final Column<Advice> alpha;

  // β = inv0(x_p)
  final Column<Advice> beta;

  // γ = inv0(x_q)
  final Column<Advice> gamma;

  // δ = inv0(y_p + y_q) if x_q = x_p, 0 otherwise
  final Column<Advice> delta;

  const AddConfig({
    required this.qAdd,
    required this.lambda,
    required this.xP,
    required this.yP,
    required this.xQr,
    required this.yQr,
    required this.alpha,
    required this.beta,
    required this.gamma,
    required this.delta,
  });

  // --------------------------------------------------------------------------
  // Configuration
  // --------------------------------------------------------------------------

  factory AddConfig.configure(
    ConstraintSystem meta,
    Column<Advice> xP,
    Column<Advice> yP,
    Column<Advice> xQr,
    Column<Advice> yQr,
    Column<Advice> lambda,
    Column<Advice> alpha,
    Column<Advice> beta,
    Column<Advice> gamma,
    Column<Advice> delta,
  ) {
    meta.enableEquality(xP);
    meta.enableEquality(yP);
    meta.enableEquality(xQr);
    meta.enableEquality(yQr);

    final config = AddConfig(
        qAdd: meta.selector(),
        xP: xP,
        yP: yP,
        xQr: xQr,
        yQr: yQr,
        lambda: lambda,
        alpha: alpha,
        beta: beta,
        gamma: gamma,
        delta: delta);

    config._createGate(meta);
    return config;
  }
  Set<Column<Advice>> outputColumns() => {xQr, yQr};

  void _createGate(ConstraintSystem meta) {
    // https://p.z.cash/halo2-0.1:ecc-complete-addition
    meta.createGate((meta) {
      final qAdd = meta.querySelector(this.qAdd);

      final xP = meta.queryAdvice(this.xP, Rotation.cur());
      final yP = meta.queryAdvice(this.yP, Rotation.cur());
      final xQ = meta.queryAdvice(xQr, Rotation.cur());
      final yQ = meta.queryAdvice(yQr, Rotation.cur());
      final xR = meta.queryAdvice(xQr, Rotation.next());
      final yR = meta.queryAdvice(yQr, Rotation.next());
      final lambda = meta.queryAdvice(this.lambda, Rotation.cur());

      final alpha = meta.queryAdvice(this.alpha, Rotation.cur());
      final beta = meta.queryAdvice(this.beta, Rotation.cur());
      final gamma = meta.queryAdvice(this.gamma, Rotation.cur());
      final delta = meta.queryAdvice(this.delta, Rotation.cur());

      final xQMinusXP = xQ - xP;
      final xPMinusXR = xP - xR;
      final yQPlusYP = yQ + yP;

      final ifAlpha = xQMinusXP * alpha;
      final ifBeta = xP * beta;
      final ifGamma = xQ * gamma;
      final ifDelta = yQPlusYP * delta;

      // Constants
      final one = ExpressionConstant(PallasNativeFp.one());
      final two = ExpressionConstant(PallasNativeFp.from(2));
      final three = ExpressionConstant(PallasNativeFp.from(3));

      // ------------------------------------------------------------------
      // Polynomials
      // ------------------------------------------------------------------

      // (x_q − x_p)((x_q − x_p)λ − (y_q − y_p)) = 0
      final yQMinusYP = yQ - yP;
      final incomplete = xQMinusXP * lambda - yQMinusYP;
      final poly1 = xQMinusXP * incomplete;

      // (1 − (x_q − x_p)α)(2y_p λ − 3x_p²) = 0
      final poly2 = (one - ifAlpha) * (two * yP * lambda - three * xP.square());

      // Non-exceptional R constraints
      final nonExceptionalXR = lambda.square() - xP - xQ - xR;
      final nonExceptionalYR = lambda * xPMinusXR - yP - yR;

      final poly3a = xP * xQ * xQMinusXP * nonExceptionalXR;
      final poly3b = xP * xQ * xQMinusXP * nonExceptionalYR;
      final poly3c = xP * xQ * yQPlusYP * nonExceptionalXR;
      final poly3d = xP * xQ * yQPlusYP * nonExceptionalYR;

      // P = infinity cases
      final poly4a = (one - ifBeta) * (xR - xQ);
      final poly4b = (one - ifBeta) * (yR - yQ);

      // Q = infinity cases
      final poly5a = (one - ifGamma) * (xR - xP);
      final poly5b = (one - ifGamma) * (yR - yP);

      // P + Q = infinity
      final poly6a = (one - ifAlpha - ifDelta) * xR;
      final poly6b = (one - ifAlpha - ifDelta) * yR;

      return Constraints(selector: qAdd, constraints: [
        poly1,
        poly2,
        poly3a,
        poly3b,
        poly3c,
        poly3d,
        poly4a,
        poly4b,
        poly5a,
        poly5b,
        poly6a,
        poly6b
      ]);
    });
  }

  EccPoint assignRegion(
    EccPoint p,
    EccPoint q,
    int offset,
    Region region,
  ) {
    // Enable `q_add` selector
    qAdd.enable(region: region, offset: offset);

    // Copy point `p` into `x_p`, `y_p` columns
    p.x.copyAdvice(region, this.xP, offset);
    p.y.copyAdvice(region, this.yP, offset);

    // Copy point `q` into `x_qr`, `y_qr` columns
    q.x.copyAdvice(region, xQr, offset);
    q.y.copyAdvice(region, yQr, offset);

    final xP = p.x.value;
    final yP = p.y.value;
    final xQ = q.x.value;
    final yQ = q.y.value;

    // // Assign α = inv0(x_q - x_p)
    final alpha = xQ != null && xP != null ? (xQ - xP).invert() : null;
    region.assignAdvice(this.alpha, offset, () => alpha);

    // Assign β = inv0(x_p)
    final beta = xP?.invert();
    region.assignAdvice(this.beta, offset, () => beta);

    // Assign γ = inv0(x_q)
    final gamma = xQ?.invert();
    region.assignAdvice(this.gamma, offset, () => gamma);

    // // Assign δ = inv0(y_q + y_p) if x_q = x_p, 0 otherwise
    Assigned? delta;
    if (xP != null && xQ != null && yP != null && yQ != null) {
      if (xQ == xP) {
        delta = (yQ + yP).invert();
      } else {
        delta = AssignedZero();
      }
    }
    region.assignAdvice(this.delta, offset, () => delta);

    // // Assign λ
    Assigned? lambda;
    if (xP != null && yP != null && xQ != null && yQ != null && alpha != null) {
      if (xQ != xP) {
        // λ = (y_q - y_p)/(x_q - x_p)
        lambda = (yQ - yP) * alpha;
      } else {
        if (!yP.isZero) {
          // 3(x_p)^2
          final threeXP2 = xP.square() * PallasNativeFp.from(3);
          // 1 / 2(y_p)
          final invTwoYP = yP.invert() * PallasNativeFp.twoInv();
          // λ = 3(x_p)^2 / 2(y_p)
          lambda = threeXP2 * invTwoYP;
        } else {
          lambda = AssignedZero();
        }
      }
    }

    region.assignAdvice(this.lambda, offset, () => lambda);

    // Calculate (x_r, y_r)
    Assigned? xR;
    Assigned? yR;

    if (xP != null &&
        yP != null &&
        xQ != null &&
        yQ != null &&
        lambda != null) {
      if (xP.isZero) {
        // 0 + Q = Q
        xR = xQ;
        yR = yQ;
      } else if (xQ.isZero) {
        // P + 0 = P
        xR = xP;
        yR = yP;
      } else if ((xQ == xP) && (yQ == -yP)) {
        // P + (-P) maps to (0,0)
        xR = AssignedZero();
        yR = AssignedZero();
      } else {
        // x_r = λ^2 - x_p - x_q
        xR = lambda.square() - xP - xQ;
        // y_r = λ(x_p - x_r) - y_p
        yR = lambda * (xP - xR) - yP;
      }
    }
    final xRCell = region.assignAdvice(xQr, offset + 1, () => xR);

    final yRCell = region.assignAdvice(yQr, offset + 1, () => yR);

    return EccPoint(xRCell, yRCell);
  }
}

class AddIncompleteConfig {
  final Selector qAddIncomplete;

  /// x-coordinate of P in P + Q = R
  final Column<Advice> xP;

  /// y-coordinate of P in P + Q = R
  final Column<Advice> yP;

  /// x-coordinate of Q or R in P + Q = R
  final Column<Advice> xQr;

  /// y-coordinate of Q or R in P + Q = R
  final Column<Advice> yQr;

  const AddIncompleteConfig({
    required this.qAddIncomplete,
    required this.xP,
    required this.yP,
    required this.xQr,
    required this.yQr,
  });

  // --------------------------------------------------------------------------
  // Configuration
  // --------------------------------------------------------------------------

  factory AddIncompleteConfig.configure(
    ConstraintSystem meta,
    Column<Advice> xP,
    Column<Advice> yP,
    Column<Advice> xQr,
    Column<Advice> yQr,
  ) {
    meta.enableEquality(xP);
    meta.enableEquality(yP);
    meta.enableEquality(xQr);
    meta.enableEquality(yQr);
    final config = AddIncompleteConfig(
        qAddIncomplete: meta.selector(), xP: xP, yP: yP, xQr: xQr, yQr: yQr);
    config._createGate(meta);
    return config;
  }

  Set<Column<Advice>> adviceColumns() => {xP, yP, xQr, yQr};

  void _createGate(ConstraintSystem meta) {
    // https://p.z.cash/halo2-0.1:ecc-incomplete-addition
    meta.createGate((meta) {
      final q = meta.querySelector(qAddIncomplete);

      final xPcur = meta.queryAdvice(xP, Rotation.cur());
      final yPcur = meta.queryAdvice(yP, Rotation.cur());
      final xQ = meta.queryAdvice(xQr, Rotation.cur());
      final yQ = meta.queryAdvice(yQr, Rotation.cur());
      final xR = meta.queryAdvice(xQr, Rotation.next());
      final yR = meta.queryAdvice(yQr, Rotation.next());

      // (x_r + x_q + x_p)⋅(x_p − x_q)^2 − (y_p − y_q)^2 = 0
      final poly1 = (xR + xQ + xPcur) * (xPcur - xQ) * (xPcur - xQ) -
          (yPcur - yQ).square();

      // (y_r + y_q)(x_p − x_q) − (y_p − y_q)(x_q − x_r) = 0
      final poly2 = (yR + yQ) * (xPcur - xQ) - (yPcur - yQ) * (xQ - xR);

      return Constraints(selector: q, constraints: [poly1, poly2]);
    });
  }

  EccPoint assignRegion(EccPoint p, EccPoint q, int offset, Region region) {
    qAddIncomplete.enable(region: region, offset: offset);
    final xP = p.x.value;
    final yP = p.y.value;
    final xQ = q.x.value;
    final yQ = q.y.value;

    if (xP != null && yP != null && xQ != null && yQ != null) {
      final pIsInfinity = xP.isZero && yP.isZero;
      final qIsInfinity = xQ.isZero && yQ.isZero;
      final xEquals = xP == xQ;

      if (pIsInfinity || qIsInfinity || xEquals) {
        throw Halo2Exception.operationFailed("assignRegion",
            reason: "zero point addition.");
      }
    }

    // Copy point `p` into `x_p`, `y_p` columns
    p.x.copyAdvice(region, this.xP, offset);
    p.y.copyAdvice(region, this.yP, offset);

    // // Copy point `q` into `x_qr`, `y_qr` columns
    q.x.copyAdvice(region, xQr, offset);
    q.y.copyAdvice(region, yQr, offset);

    // // Compute the sum `P + Q = R`
    Assigned? xR;
    Assigned? yR;

    if (xP != null && yP != null && xQ != null && yQ != null) {
      // λ = (y_q - y_p) / (x_q - x_p)
      final lambda = (yQ - yP) * (xQ - xP).invert();

      // x_r = λ^2 - x_p - x_q
      xR = lambda.square() - xP - xQ;

      // y_r = λ(x_p - x_r) - y_p
      yR = lambda * (xP - xR) - yP;
    }

    // // Assign the sum to `x_qr`, `y_qr` columns in the next row
    final xRVar = region.assignAdvice(xQr, offset + 1, () => xR);
    final yRVar = region.assignAdvice(yQr, offset + 1, () => yR);
    final result = EccPoint(xRVar, yRVar);
    return result;
  }
}
