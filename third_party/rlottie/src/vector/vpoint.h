/*
 * Copyright (c) 2020 Samsung Electronics Co., Ltd. All rights reserved.

 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
#ifndef VPOINT_H
#define VPOINT_H

#include "vglobal.h"

V_BEGIN_NAMESPACE

class VPointF {
public:
    VPointF() = default;
    inline VPointF(float x, float y)  : mx(x), my(y) {}
    inline float x() const  { return mx; }
    inline float y() const  { return my; }
    inline float &         rx()  { return mx; }
    inline float &         ry()  { return my; }
    inline void            setX(float x) { mx = x; }
    inline void            setY(float y) { my = y; }
    inline VPointF         operator-()  { return {-mx, -my}; }
    inline VPointF &       operator+=(const VPointF &p) ;
    inline VPointF &       operator-=(const VPointF &p) ;
    friend const VPointF   operator+(const VPointF &p1, const VPointF &p2)
    {
        return VPointF(p1.mx + p2.mx, p1.my + p2.my);
    }
    inline friend bool fuzzyCompare(const VPointF &p1, const VPointF &p2);
    inline friend VDebug &   operator<<(VDebug &os, const VPointF &o);

    friend inline VPointF       operator-(const VPointF &p1, const VPointF &p2);
    friend inline const VPointF operator*(const VPointF &, float);
    friend inline const VPointF operator*(float, const VPointF &);
    friend inline const VPointF operator/(const VPointF &, float);
    friend inline const VPointF operator/(float, const VPointF &);

private:
    float mx{0};
    float my{0};
};

inline bool fuzzyCompare(const VPointF &p1, const VPointF &p2)
{
    return (vCompare(p1.mx, p2.mx) && vCompare(p1.my, p2.my));
}

inline VPointF operator-(const VPointF &p1, const VPointF &p2)
{
    return {p1.mx - p2.mx, p1.my - p2.my};
}

inline const VPointF operator*(const VPointF &p, float c)
{
    return VPointF(p.mx * c, p.my * c);
}

inline const VPointF operator*(float c, const VPointF &p)
{
    return VPointF(p.mx * c, p.my * c);
}

inline const VPointF operator/(const VPointF &p, float c)
{
    return VPointF(p.mx / c, p.my / c);
}

inline const VPointF operator/(float c, const VPointF &p)
{
    return VPointF(p.mx / c, p.my / c);
}

inline VDebug &operator<<(VDebug &os, const VPointF &o)
{
    os << "{P " << o.x() << "," << o.y() << "}";
    return os;
}

inline VPointF &VPointF::operator+=(const VPointF &p) 
{
    mx += p.mx;
    my += p.my;
    return *this;
}

inline VPointF &VPointF::operator-=(const VPointF &p) 
{
    mx -= p.mx;
    my -= p.my;
    return *this;
}

class VPoint {
public:
    VPoint() = default;
    inline VPoint(int x, int y)  : mx(x), my(y) {}
    inline int  x() const  { return mx; }
    inline int  y() const  { return my; }
    inline void           setX(int x) { mx = x; }
    inline void           setY(int y) { my = y; }
    inline VPoint &       operator+=(const VPoint &p) ;
    inline VPoint &       operator-=(const VPoint &p) ;
    const inline bool operator==(const VPoint &o) const;
    inline bool operator!=(const VPoint &o) const
    {
        return !(operator==(o));
    }
    friend inline VPoint  operator-(const VPoint &p1, const VPoint &p2);
    inline friend VDebug &operator<<(VDebug &os, const VPoint &o);

private:
    int mx{0};
    int my{0};
};
inline VDebug &operator<<(VDebug &os, const VPoint &o)
{
    os << "{P " << o.x() << "," << o.y() << "}";
    return os;
}

inline VPoint operator-(const VPoint &p1, const VPoint &p2)
{
    return {p1.mx - p2.mx, p1.my - p2.my};
}

const inline bool VPoint::operator==(const VPoint &o) const
{
    return (mx == o.x() && my == o.y());
}

inline VPoint &VPoint::operator+=(const VPoint &p) 
{
    mx += p.mx;
    my += p.my;
    return *this;
}

inline VPoint &VPoint::operator-=(const VPoint &p) 
{
    mx -= p.mx;
    my -= p.my;
    return *this;
}

class VSize {
public:
    VSize() = default;
    inline VSize(int w, int h)  : mw(w), mh(h) {}
    bool empty() const {return (mw <= 0 || mh <= 0);}
    inline int  width() const  { return mw; }
    inline int  height() const  { return mh; }
    inline void           setWidth(int w) { mw = w; }
    inline void           setHeight(int h) { mh = h; }
    inline VSize &        operator+=(const VSize &p) ;
    inline VSize &        operator-=(const VSize &p) ;
    const inline bool operator==(const VSize &o) const;
    inline bool operator!=(const VSize &o) const
    {
        return !(operator==(o));
    }
    inline friend VDebug &operator<<(VDebug &os, const VSize &o);

private:
    int mw{0};
    int mh{0};
};
inline VDebug &operator<<(VDebug &os, const VSize &o)
{
    os << "{P " << o.width() << "," << o.height() << "}";
    return os;
}
const inline bool VSize::operator==(const VSize &o) const
{
    return (mw == o.width() && mh == o.height());
}

inline VSize &VSize::operator+=(const VSize &p) 
{
    mw += p.mw;
    mh += p.mh;
    return *this;
}

inline VSize &VSize::operator-=(const VSize &p) 
{
    mw -= p.mw;
    mh -= p.mh;
    return *this;
}

V_END_NAMESPACE

#endif  // VPOINT_H
