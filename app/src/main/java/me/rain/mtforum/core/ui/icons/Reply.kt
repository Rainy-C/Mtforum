// Copyright 2025, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0

package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

/** The original Miuix Regular Reply icon vector. */
val MiuixNavigationIcons.Reply: ImageVector
    get() {
        if (_replyRegular != null) return _replyRegular!!
        _replyRegular =
            ImageVector.Builder(
                    name = "Reply.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1264.8f,
                    viewportHeight = 1264.8f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1264.8f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(1159.4f, 686.9f),
                                    PathNode.QuadTo(1159.4f, 809.9f, 1087.9f, 908.9f),
                                    PathNode.QuadTo(1016.4f, 1007.9f, 895.4f, 1064.4f),
                                    PathNode.QuadTo(774.4f, 1120.9f, 632.4f, 1120.9f),
                                    PathNode.QuadTo(500.4f, 1120.9f, 378.4f, 1066.9f),
                                    PathNode.QuadTo(256.4f, 1012.9f, 180.9f, 913.9f),
                                    PathNode.QuadTo(105.4f, 814.9f, 105.4f, 686.9f),
                                    PathNode.QuadTo(105.4f, 596.9f, 145.9f, 519.4f),
                                    PathNode.QuadTo(186.4f, 441.9f, 255.4f, 383.9f),
                                    PathNode.QuadTo(324.4f, 325.9f, 409.4f, 292.9f),
                                    PathNode.QuadTo(416.4f, 290.9f, 419.9f, 284.4f),
                                    PathNode.QuadTo(423.4f, 277.9f, 421.4f, 269.9f),
                                    PathNode.LineTo(387.4f, 155.9f),
                                    PathNode.QuadTo(385.4f, 150.9f, 389.4f, 147.4f),
                                    PathNode.QuadTo(393.4f, 143.9f, 399.4f, 144.9f),
                                    PathNode.LineTo(745.4f, 244.9f),
                                    PathNode.QuadTo(935.4f, 299.9f, 1047.4f, 403.9f),
                                    PathNode.QuadTo(1159.4f, 507.9f, 1159.4f, 686.9f),
                                    PathNode.Close,
                                    PathNode.MoveTo(441.4f, 377.9f),
                                    PathNode.QuadTo(374.4f, 402.9f, 318.9f, 447.9f),
                                    PathNode.QuadTo(263.4f, 492.9f, 229.9f, 554.4f),
                                    PathNode.QuadTo(196.4f, 615.9f, 196.4f, 686.9f),
                                    PathNode.QuadTo(196.4f, 788.9f, 259.4f, 867.4f),
                                    PathNode.QuadTo(322.4f, 945.9f, 422.9f, 988.4f),
                                    PathNode.QuadTo(523.4f, 1030.9f, 632.4f, 1030.9f),
                                    PathNode.QuadTo(756.4f, 1030.9f, 855.9f, 983.4f),
                                    PathNode.QuadTo(955.4f, 935.9f, 1011.9f, 856.9f),
                                    PathNode.QuadTo(1068.4f, 777.9f, 1068.4f, 686.9f),
                                    PathNode.QuadTo(1068.4f, 585.9f, 1022.4f, 515.9f),
                                    PathNode.QuadTo(976.4f, 445.9f, 900.4f, 403.4f),
                                    PathNode.QuadTo(824.4f, 360.9f, 719.4f, 330.9f),
                                    PathNode.LineTo(512.4f, 270.9f),
                                    PathNode.QuadTo(514.4f, 305.9f, 494.9f, 335.4f),
                                    PathNode.QuadTo(475.4f, 364.9f, 441.4f, 377.9f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _replyRegular!!
    }

private var _replyRegular: ImageVector? = null
